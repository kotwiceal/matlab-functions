classdef cfic < handle
properties (Access = public)
    folder {mustBeFolder} = pwd
    lcard lcard
    mcu mcu
    figures struct
    bsize (1,1) {mustBeInteger, mustBePositive} = 1 % batch size
    bdata (1,:) cell % batch data
    pdata struct % process data
    process function_handle = @(x)struct(ymean=mean(cat(ndims(x{1}),x{:}),[2,3])); % sensor data process function handle 
    result (1,:) cell % optimization result
    pool parallel.Pool
    dq struct % data queue
    pdq struct % pollable data queue
    ff struct % feval future
    ac {mustBeVector} = ones(1,32) % actuator calibration
end
properties (Access = private)
    dql (:,1) cell = {'log';'batch';'postprocess';'progress';'terminate';'complete'} % data queue label
    pdql (:,1) cell = {'postprocess'} % pollable data queue label
    ffl (:,1) cell = {'process';'optimize'} % feval future label
    figl (:,1) cell = {'postprocess';'optimization'} % figure labels
    ladc struct % LCard ADC parameters
end
methods (Access = public)
    function  obj = cfic(folder)
        arguments
            folder {mustBeFolder} = pwd
        end
        obj.folder = folder;
        % define data queues
        obj.dq = cell2struct(cellfun(@(x)parallel.pool.DataQueue,obj.dql,'UniformOutput',false),obj.dql);
        % define pollable data queues
        obj.pdq = cell2struct(cellfun(@(x)parallel.pool.PollableDataQueue,obj.pdql,'UniformOutput',false),obj.pdql);
        % define feval future
        obj.ff = cell2struct(cellfun(@(x)parallel.FevalFuture,obj.ffl,'UniformOutput',false),obj.ffl);
        % define handlers
        afterEach(obj.dq.log,@(x)fprintf("%s %s\n",datetime,x))
        afterEach(obj.dq.batch,@obj.batch)
        afterEach(obj.dq.postprocess,@obj.postprocess)
        afterEach(obj.dq.progress,@obj.progress)
        afterEach(obj.dq.terminate,@obj.terminate)
        afterEach(obj.dq.complete,@obj.complete)
        % define lcard
        obj.lcard = lcard('dqlog',obj.dq.log);
        % define mcu
        obj.mcu = mcu('dqlog',obj.dq.log);
        % define figures
        obj.figures = cell2struct(cellfun(@(x)figure('Name',x,'WindowStyle','docked','NumberTitle','off','Visible','off'),...
            obj.figl,'UniformOutput',false),obj.figl);
    end
    function batch(obj,data)
        arguments
            obj
            data (:,:) double 
        end
        obj.bdata = cat(2,obj.bdata,{data});
        if gt(numel(obj.bdata),obj.bsize-1)
            args = {obj.dq.postprocess,obj.process,obj.bdata};
            obj.ff.process = parfeval(obj.pool,@(q,f,x)send(q,f(x)),0,args{:});
            obj.bdata = {};
        end
    end
    function postprocess(obj,data)
        arguments
            obj 
            data (1,1) struct
        end
        % store postprocess data
        obj.pdata = data;
        % show postprocess data
        flabel = 'postprocess';
        f = obj.figures.(flabel); 
        if ~isvalid(f)
            f = figure('Name',flabel,'WindowStyle','docked','NumberTitle','off');
            obj.figures.(flabel) = f; 
        end
        set(f,'Visible','on'); t = tiledlayout(f); delete(t.Children);

        ax = nexttile(t); hold(ax,'on'); grid(ax,'on'); box(ax,'on'); pbaspect([2,1,1]);
        cellfun(@(x,i)[plot(data.time,x,'.-'),plot(data.time(find(i)),x(i),'-o','MarkerFaceColor','auto')],...
            data.ref,data.refi,'UniformOutput',false);
        xlabel(ax,'t, s'); ylabel(ax,'amplitude, V'); subtitle(ax,'reference signal');

        ax = nexttile(t); hold(ax,'on'); grid(ax,'on'); box(ax,'on'); pbaspect([2,1,1]);
        plot(ax,data.freq,data.spec); 
        l = legend(ax,num2str(data.chan(:)),'NumColumns',4,'visible','off'); 
        title(l,'channel','FontWeight','normal');
        set(ax,'xscale','log','yscale','log');
        xlabel(ax,'f, Hz'); ylabel(ax,'PSD, (1/s)^2/Hz'); subtitle(ax,'sensor auto-spectra');

        ax = nexttile(t); hold(ax,'on'); grid(ax,'on'); box(ax,'on'); pbaspect([2,1,1]);
        plot(ax,data.time,data.sens);
        l = legend(ax,num2str(data.chan(:)),'NumColumns',4,'visible','off'); 
        title(l,'channel','FontWeight','normal');
        xlabel(ax,'t, s'); ylabel(ax,'du/dy, 1/s'); subtitle(ax,'sensor signal');

        ax = nexttile(t); hold(ax,'on'); grid(ax,'on'); box(ax,'on'); pbaspect([2,1,1]);
        plot(ax,data.chan,data.zsens,'-o','MarkerFaceColor','auto');
        xlabel(ax,'channel'); ylabel(ax,'$\overline{du/dy}$, 1/s','Interpreter','latex'); 
        subtitle('spanwise sensor signal')
        
        sgtitle(f,string(datetime))
    end
    function data = exite(obj,x,i)
        arguments
            obj 
            x {mustBeVector}
            i {mustBeVector,mustBeInteger,mustBePositive}
        end
        data = cfic.hexite(x,i,obj.ac,obj.mcu,obj.lcard,obj.process,obj.bsize,parallel.pool.DataQueue);
    end
    function optimize(obj,problem,index,options)
        arguments
            obj 
            problem (1,1) struct
            index {mustBeVector}
            options.parallel (1,1) logical = false
        end
        % reset
        obj.bdata = {}; obj.result = [];
        % wrap by constant
        cmcu = parallel.pool.Constant(obj.mcu);
        clcard = parallel.pool.Constant(obj.lcard);

        % stack args
        acalib = obj.ac;
        dqprogress = obj.dq.progress;
        bsize = obj.bsize;
        process = obj.process;
        exite = @(x,m,l)cfic.hexite(x,index,acalib,m,l,process,bsize,dqprogress);
        args = {cmcu,clcard,problem,exite,obj.dq.log,obj.dq.terminate,obj.dq.complete};

        if options.parallel
            % create pool
            if isa(gcp('nocreate'),'parallel.ProcessPool')
                obj.pool = gcp;
            else
                delete(gcp('nocreate'))
                obj.pool = parpool('Processes',2);
            end
            obj.pdq.postprocess = parallel.pool.PollableDataQueue;
            obj.ff.optimize = parfeval(obj.pool,...
                @(cm,cl,varargin)cfic.optimization(cm.Value,cl.Value,varargin{:}),0,args{:});
        else
            cfic.optimization(args{1}.Value,args{2}.Value,args{3:end});
        end
    end
    function terminate(obj,state)
        if state
            obj.pdq.postprocess.close;
            cancel(obj.ff.optimize)
            send(obj.dq.log,"optimization is terminated")
        end
    end
    function progress(obj,data)
        arguments
            obj 
            data (1,1) struct
        end
        % concatenate results
        obj.result = cat(2,obj.result,{data});
        
        l = 3;
        n = numel(obj.result);
        if n > l; m = (n-l+1):n; else; m = 1:n; end
        xdata = cellfun(@(x)x.actuator.dac.value,obj.result,'UniformOutput',false);
        xdata = cat(2,xdata{:}); xdata = xdata(:,m);
        k = unique([1,m]);
        ydata = cellfun(@(x)x.sensor.zsens,obj.result,'UniformOutput',false);
        ydata = cat(2,ydata{:}); ydata = ydata(:,k);

        objval = cellfun(@(x)x.sensor.objval,obj.result);

        flabel = 'optimization';
        f = obj.figures.(flabel); 
        if ~isvalid(f)
            f = figure('Name',flabel,'WindowStyle','docked','NumberTitle','off');
            obj.figures.(flabel) = f; 
        end
        set(f,'Visible','on'); t = tiledlayout(f); delete(t.Children);
        if isempty(t.Children)
            arrayfun(@(x)set(nexttile(t),'Box','on','XGrid','on','YGrid','on'),1:3)
            arrayfun(@(x)hold(x,'on'),t.Children)
        end
        axs = flip(findobj(t,'type','Axes'));
        arrayfun(@(x)cla(x),axs);
        colors = colororder;

        ax = axs(1);
        p = plot(ax,xdata,'-o','Color',colors(1,:),'MarkerFaceColor','auto');
        xlabel(ax,'channel'); ylabel(ax,'amplitude')
        if ~isscalar(p); arrayfun(@(p,c)set(p,'Color',[p.Color,0.25]),p(1:end-1)); end
        subtitle(ax,'actuator'); l = legend(ax,split(num2str(m)),'Location','eastoutside');
        title(l,'iteration')

        ax = axs(2);
        p = plot(ax,ydata,'-o','Color',colors(1,:),'MarkerFaceColor','auto');
        xlabel(ax,'channel'); ylabel(ax,'amplitude')
        if ~isscalar(p); arrayfun(@(p,c)set(p,'Color',[p.Color,0.25]),p(1:end-1)); end
        set(p(1),'Color',colors(2,:));
        labels = split(num2str(k));
        subtitle(ax,'sensor'); l = legend(ax,labels,'Location','eastoutside');
        title(l,'iteration')

        ax = axs(3);
        plot(ax,objval,'-o','MarkerFaceColor','auto')
        yline(ax,objval(1),'-','reference','LabelHorizontalAlignment','left','Color',colors(2,:));
        xlabel('iteration'); ylabel('objective function')
    end
    function complete(obj,x)
        obj.pdq.postprocess.close;
        % save results
        filename = string(datetime('now','Format','yyyy-MM-dd HH-mm-ss'));
        filename = fullfile(obj.folder,strcat(filename,'.mat'));
        data = obj.result;
        optres = x;
        save(filename,'data','optres')
        send(obj.dq.log, sprintf("save optimization result to %s",filename))
        % modify optimization figure
        colors = colororder; color = colors(5,:);
        f = obj.figures.optimization;
        ax = flip(findobj(f,'type','Axes'));
        ax(1).Children(1).Color = color;
        ax(2).Children(1).Color = color;
        yline(ax(3),x.fval,'-','optimum','LabelHorizontalAlignment','right',...
            'Color',color)
    end
    function y = actuate(obj,x,i)
        arguments (Input)
            obj 
            x {mustBeVector}
            i {mustBeVector}
        end
        arguments (Output)
            y (1,1) struct
        end
        y = cfic.hactuate(obj.mcu,x,i,obj.ac);
    end
    function delete(obj)
        structfun(@(x)cancel(x),obj.ff)
        structfun(@(x)delete(x),obj.dq)
    end
end
methods (Static)
    function y = hactuate(m,x,i,ac)
        arguments (Input)
            m mcu
            x {mustBeVector} % amplitudes
            i {mustBeVector} % channels
            ac {mustBeVector} % calibration
        end
        arguments (Output)
            y (1,1) struct
        end
        ac = ac(:);
        x = ac(i).*x(:);
        m.set(struct(dac=struct(value=x,index=i-1)));
        y = m.get();
    end
    function y = hprocess(x,options)
        arguments (Input)
            x (1,:) cell % data
            options.sch {mustBeVector} % sensor channel
            options.sel {mustBeMember(options.sel,{'phase','all'})} = 'phase' % select sample index mode
            options.proc {mustBeMember(options.proc,{'mean','var'})} = 'mean' % sample process method
            options.norm (1,1) {mustBeInteger,mustBePositive} = 2 % norm order
            options.si (1,:) {mustBeInteger,mustBePositive} = 1:32 % signal indexes
            options.rch (1,1) {mustBeInteger,mustBePositive} = 1 % reference signal index
            options.thr (1,1) double = 1.6 % reference signal threshold
            options.rtol (1,1) double = 0.02 % relative tolerance
            options.ft (1,:) cell % calibration fit object
            options.fch {mustBeVector} % calibration fit channel
            options.fillmissing {mustBeMember(options.fillmissing,{'','linear','nearest'})} = 'nearest'
            options.fs (1,1) double = 1 % sample frequency
            options.winlen (1,:) double = nan % fft window length
            options.overlap (1,:) double = nan % fft window overlap
        end
        arguments (Output)
            y (1,1) struct
        end
        n = numel(options.si); fs = options.fs/n;
        % get sensor signal index;
        if isfield(options,'sch')
            sch = options.sch;
        else
            sch = sort(options.si); sch(options.rch) = [];
        end
        % get reference data
        rd = cellfun(@(x)x(options.rch,:),x,'UniformOutput',false);
        % cell split by channels
        sd = cellfun(@(x)mat2cell(x,ones(1,size(x,1)),size(x,2)),x,'UniformOutput',false);
        % appply sensor calibration
        if isfield(options,'ft')
            ft = options.ft;
            if isfield(options,'fch')
                temp = repmat({@(x)nan(size(x))},n,1);
                temp(options.fch) = ft; ft = temp;
            else
                error('fit cell array size must be same ADC channels')
            end
        else
            ft = repmat({@(x)nan(size(x))},n,1);
            ft(sch) = repmat({@(x)x},numel(sch),1);
        end
        sd = cellfun(@(x)cellfun(@(f,y)reshape(f(y),size(y)),ft,x,'UniformOutput',false),sd,'UniformOutput',false);
        % concatenate by channels
        sd = cellfun(@(x)squeeze(cat(ndims(x{1})+1,x{:})),sd,'UniformOutput',false);
        % to store one batch
        sens = sd{1}; time = 0:1/fs:1/fs*(size(sens,1)-1);
        % precess auto-spectra
        spec = squeeze(cat(ndims(sd{1})+1,sd{:})); 
        ind = isnan(spec); spec(ind) = 0;
        [spec,freq] = procspecn(spec,'ftdim',1,...
            'winlen',options.winlen,'overlap',options.overlap,...
            'side','single','type','psd','fs',fs,'norm',true,'center',true);
        % spec(ind) = nan;
        % batch average
        spec = mean(spec,3); 
        % select sample index
        switch options.sel
            case 'phase'
                rdi = cellfun(@(x)isapprox(x,options.thr,'RelativeTolerance',options.rtol),rd,'UniformOutput',false);
            case 'all'
                rdi = cellfun(@(x)true(1,numel(x)),rd,'UniformOutput',false);
        end
        % select semple process method
        switch options.proc
            case 'mean'
                fnc = @(x)mean(x,1);
            case 'var'
                fnc = @(x)sqrt(var(x,[],1));
        end
        % phase/all sample processing by given method
        sd = cellfun(@(x,i)fnc(x(i,:)),sd,rdi,'UniformOutput',false);
        % batch average
        sd = mean(squeeze(cat(ndims(sd{1})+1,sd{:})),2);
        % fill missing
        if ~isempty(options.fillmissing)
            sd = fillmissing(sd,options.fillmissing);
        end
        sch = options.si;
        % store
        y = struct;
        y.adc = cat(ndims(x{1})+1,x{:});
        y.ref = rd(1); % reference signal data
        y.refi = rdi(1); % reference signal index
        y.chan = sch; % sensor channel idnexes
        y.zsens = sd; % batch and sample averaged transversal amplitude profile
        y.objval = norm(y.zsens,options.norm); % objective function value
        y.spec = spec; % auto-spectra
        y.freq = freq; % frequency vector
        y.sens = sens; % sensor sample data
        y.time = time; % time vector
    end
    function data = hexite(x,i,ac,m,l,p,b,dq,options)
        arguments (Input)
            x {mustBeVector} % actuator control vector
            i {mustBeVector} % actuator index
            ac {mustBeVector} % actuator calibration
            m mcu
            l lcard
            p function_handle % process handle
            b (1,1) {mustBeInteger,mustBePositive} % batch size
            dq (1,:) parallel.pool.DataQueue % send to data queue
            options.pause {mustBePositive} = 0.5 % delay between action and response
        end
        arguments (Output)
            data (1,1) struct
        end
        x = cfic.hactuate(m,x,i,ac);
        pause(options.pause)
        y = p(arrayfun(@(x)l.adcread(),1:b,'UniformOutput',false));
        data = struct(actuator=x,sensor=y);
        arrayfun(@(q)send(q,data),dq);
    end
    function optimization(m,l,problem,exite,dqlog,dqterminate,dqcomplete)
        arguments
            m mcu
            l lcard
            problem (1,1) struct
            exite function_handle
            dqlog (1,1) parallel.pool.DataQueue % to log
            dqterminate (1,1) parallel.pool.DataQueue % to terminate execution
            dqcomplete (1,1) parallel.pool.DataQueue % to send result to main worker
        end
        d = dbstack; flabel = sprintf("@%s:",d(1).name);
        try
            exite = @(x)exite(x,m,l);
            fobj = @(x)getfield(getfield(exite(x),'sensor'),'objval'); % objective function
            switch class(problem.options)
                case 'optim.options.Fmincon'
                    method = @fmincon;
                    problem.solver = 'fmincon';
                    problem.objective = fobj;
                case 'optim.options.GaOptions'
                    method = @ga;
                    problem.solver = 'ga';
                    problem.nvars = numel(problem.x0);
                    problem.fitnessfcn = fobj;
            end
            
            send(dqlog,sprintf("%s evaluate reference state",flabel))
            exite(zeros(numel(problem.x0),1));
            
            lab = {'x';'fval';'exitflag';'output'}; result = cell(numel(lab),1);
            send(dqlog,sprintf("%s start optimization",flabel))
            [result{:}] = method(problem);
            result = cell2struct(result,lab);
            send(dqlog,sprintf("%s optimization is completed",flabel))

            send(dqlog,sprintf("%s evaluate optimal state",flabel))
            exite(result.x);

            send(dqlog,sprintf("%s optimization is finished",flabel))
            send(dqcomplete,result)
        catch ex
            send(dqlog,sprintf("%s optimization if failed: %s",flabel,ex.message))
            send(dqterminate,true);
            rethrow(ex)
        end
    end
end
end