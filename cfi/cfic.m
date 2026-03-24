classdef cfic < handle
properties (Access = public)
    folder {mustBeFolder} = pwd
    lcard lcard
    mcu mcu
    figures struct
    bsize (1,1) {mustBeInteger, mustBePositive} = 1 % batch size
    bdata (1,:) cell % batch data
    pdata struct % process data
    process function_handle = @(x)struct(zsens=mean(cat(ndims(x{1}),x{:}),[2,3])); % sensor data process function handle 
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
    temporary struct = struct(x=[],y=[],v=[])
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
        set(f,'Visible','on'); t = f.Children;
        if isempty(t)
            t = tiledlayout(f);
            if isempty(t.Children)
                arrayfun(@(x)set(nexttile(t),'Box','on','XGrid','on','YGrid','on'),1:4)
                arrayfun(@(x)hold(x,'on'),t.Children)
                arrayfun(@(x)pbaspect(x,[2,1,1]),t.Children)
            end
        end
        axs = flip(findobj(t,'type','Axes'));
        arrayfun(@(x)cla(x),axs);

        ax = axs(1);
        cellfun(@(x,i)[plot(ax,data.time,x,'.-'),plot(ax,data.time(find(i)),x(i),'-o','MarkerFaceColor','auto')],...
            data.ref,data.refi,'UniformOutput',false);
        xlabel(ax,'t, s'); ylabel(ax,'amplitude, V'); subtitle(ax,'reference signal');

        ax = axs(2);
        plot(ax,data.freq,data.spec); 
        l = legend(ax,num2str(data.chan(:)),'NumColumns',4,'visible','off'); 
        title(l,'channel','FontWeight','normal');
        set(ax,'xscale','log','yscale','log');
        xlabel(ax,'f, Hz'); ylabel(ax,'PSD, (1/s)^2/Hz'); subtitle(ax,'sensor auto-spectra');

        ax = axs(3);
        plot(ax,data.time,data.sens);
        l = legend(ax,num2str(data.chan(:)),'NumColumns',4,'visible','off'); 
        title(l,'channel','FontWeight','normal');
        xlabel(ax,'t, s'); ylabel(ax,'du/dy, 1/s'); subtitle(ax,'sensor signal');

        ax = axs(4);
        xlabel(ax,'channel'); ylabel(ax,'<du/dy>, 1/s'); 
        subtitle(ax,'spanwise sensor signal')
        plot(ax,data.chan,data.zsens,'-o','MarkerFaceColor','auto');
        plot(ax,data.chan,rescale(data.winfun,min(data.zsens(:)),max(data.zsens(:))));

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
        obj.bdata = {}; obj.result = []; obj.temporary = struct(x=[],y=[],v=[]);
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
        k = unique([1,m]);

        xch = obj.result{1}.actuator.channel;
        obj.temporary.x = cat(2, obj.temporary.x, obj.result{end}.actuator.action(:));
        x = obj.temporary.x(:,m);
        obj.temporary.y = cat(2, obj.temporary.y, obj.result{end}.sensor.zsens(:)); 
        y = obj.temporary.y(:,k);
        obj.temporary.v = cat(2, obj.temporary.v, obj.result{end}.sensor.objval);

        flabel = 'optimization';
        f = obj.figures.(flabel); 
        if ~isvalid(f)
            f = figure('Name',flabel,'WindowStyle','docked','NumberTitle','off');
            obj.figures.(flabel) = f; 
        end
        set(f,'Visible','on'); t = f.Children;
        if isempty(t)
            t = tiledlayout(f);
            if isempty(t.Children)
                arrayfun(@(x)set(nexttile(t),'Box','on','XGrid','on','YGrid','on'),1:3)
                arrayfun(@(x)hold(x,'on'),t.Children)
            end
        end
        axs = flip(findobj(t,'type','Axes'));
        arrayfun(@(x)cla(x),axs);
        colors = colororder;

        ax = axs(1);
        p = plot(ax,xch,x,'-o','Color',colors(1,:),'MarkerFaceColor','auto');
        set(p(end),'MarkerFaceColor',get(p(end),'Color'));
        xlabel(ax,'channel'); ylabel(ax,'amplitude')
        arrayfun(@(p,c)set(p,'MarkerSize',3),p(1:end-1));
        if ~isscalar(p); arrayfun(@(p,c)set(p,'Color',[p.Color,0.25]),p(1:end-1)); end
        subtitle(ax,'actuator'); l = legend(ax,split(num2str(m)),'Location','eastoutside');
        title(l,'iteration','FontWeight','normal')

        ax = axs(2);
        p = plot(ax,y,'-o','Color',colors(1,:),'MarkerFaceColor','auto');
        xlabel(ax,'channel'); ylabel(ax,'amplitude')
        if ~isscalar(p); arrayfun(@(p,c)set(p,'Color',[p.Color,0.25]),p(1:end-1)); end
        set(p(1),'Color',colors(2,:),'MarkerFaceColor',colors(2,:)); set(p(end),'MarkerFaceColor',get(p(end),'Color'));
        arrayfun(@(p,c)set(p,'MarkerSize',3),p(2:end));
        labels = split(num2str(k));
        subtitle(ax,'sensor'); l = legend(ax,labels,'Location','eastoutside');
        title(l,'iteration','FontWeight','normal')

        ax = axs(3);
        plot(ax,obj.temporary.v,'-o','MarkerFaceColor','auto')
        yline(ax,obj.temporary.v(1),'-','reference','LabelHorizontalAlignment','left','Color',colors(2,:));
        xlabel('iteration'); ylabel('objective function')

        sgtitle(f,string(datetime))
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
    function response = identify(obj,amplitude,options)
        arguments (Input)
            obj
            amplitude {mustBeVector}
            options.ach {mustBeVector} = 1:32 % actuator channel
            options.folder {mustBeFolder}
        end
        ach = options.ach;
        action = eye(numel(ach));
        action = mat2cell(action,ones(1,size(action,1)),size(action,2));
        action = cell2mat(repelem(action,numel(amplitude))).*repmat(amplitude(:),numel(ach),1);

        d = dbstack; flabel = sprintf("@%s:",d(1).name);
        send(obj.dq.log,sprintf("%s evaluate reference state",flabel))
        response = struct;
        response.reference = obj.exite(zeros(1,32),1:32);
        send(obj.dq.log,sprintf("%s evaluate actuating state",flabel))
        action = mat2cell(action,ones(1,size(action,1)),size(action,2));
        response.actuate = cellfun(@(x)obj.exite(x,options.ach),action,'UniformOutput',false);
        obj.actuate(zeros(1,32),1:32)

        sch = response.reference.sensor.sch;
        y = response.reference.sensor.zsens(sch);
        y = y(:);
        P = cellfun(@(x)x.sensor.zsens(sch),response.actuate,'UniformOutput',false);
        P = squeeze(cat(ndims(P{1})+1,P{:}));
        P = P - y;
        P = reshape(P,sch,ach,[]);

        response = struct(P=P,ach=ach,sch=sch,amp=amplitude);

        if isfield(options,'folder')
            filename = string(datetime('now','Format','yyyy-MM-dd HH-mm-ss'));
            filename = fullfile(options.folder,strcat(filename,'.mat'));
            save(filename,'response')
            fprintf('save results into %s\n',filename)
        end
    end
    function data = estimateNoise(obj,number)
        arguments
            obj
            number (1,1) double
        end
        data = arrayfun(@(x)obj.exite(zeros(1,32),1:32),1:number,'UniformOutput',false);
        objval = cellfun(@(x)x.sensor.objval,data);
        
        objvalm = mean(objval,"all");
        objvalr = sqrt(var(objval,[],"all"));
        fprintf("number estimation=%d; mean=%f; variance=%f\n",number,objvalm,objvalr)
        
        figure('WindowStyle','docked'); hold on; box on; grid on; axis square;
        [bmin,bmax] = bounds(objval(:)); b = linspace(bmin,bmax,numel(objval));
        [n,e] = histcounts(objval,b,'Normalization','count'); e = e(2:end)-diff(e,1,2);
        plot(e,n,'-o','MarkerFaceColor','auto'); xlabel('objective function'); ylabel('count');
        subtitle('statisitcs');
        xline(objvalm,'-','mean');
        xregion(objvalm-objvalr/2,objvalm+objvalr/2)
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
        t = zeros(size(ac)); t(i) = x;
        x = ac(:).*t(:);
        m.set(struct(dac=struct(value=x,index=i-1)));
        y = m.get();
    end
    function y = hprocess(x,options)
        arguments (Input)
            x (1,:) cell % data
            options.sch {mustBeVector} % sensor channel
            options.sel {mustBeMember(options.sel,{'phase','all'})} = 'phase' % select sample index mode
            options.selalg {mustBeMember(options.selalg,{'isapprox','islocalmax'})} = 'islocalmax' % select sample algorithm
            options.idxshft (1,1) double = 0 % index shift
            options.phshft (1,1) double = 0 % phase shift [deg]
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
            options.subref {mustBeVector}
            options.center (1,1) logical = true
            options.winfun {mustBeVector}
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
            'side','single','type','psd','fs',fs,'norm',true,'center',true,'avg',true);
        % batch average
        spec = mean(spec,3); 
        % select sample indexes
        switch options.sel
            case 'phase'
                switch options.selalg
                    case 'isapprox'
                        rdi = cellfun(@(x)isapprox(x,options.thr,'RelativeTolerance',options.rtol),rd,'UniformOutput',false);
                    case 'islocalmax'
                        rdi = cellfun(@(x)islocalmax(x),rd,'UniformOutput',false);
                        pd = cellfun(@(x)round(deg2rad(options.phshft)*mean(diff(find(x))/(2*pi),'all')),rdi,'UniformOutput',false);
                        options.idxshft = pd{1};
                end
                % shift index
                rdi = cellfun(@(x)ismember(1:numel(x),find(x)+options.idxshft),rdi,'UniformOutput',false);
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
        sd = cellfun(@(x,i)reshape(fnc(x(i,:)),[],1),sd,rdi,'UniformOutput',false);
        % batch average
        sd = mean(squeeze(cat(ndims(sd{1})+1,sd{:})),2,'omitmissing');
        % fill missing
        if ~isempty(options.fillmissing)
            sd = fillmissing(sd,options.fillmissing);
        end
        sch = options.si;
        if isfield(options,'subref')
            sd = sd - options.subref;
        end
        if options.center; sd = sd - mean(sd,'all','omitmissing'); end
        if ~isfield(options,'winfun')
            options.winfun = ones(1,numel(sd));
        end
        % weight by window
        sd = sd(:).*options.winfun(:);
        % store
        y = struct;
        y.adc = x;
        y.ref = rd(1); % reference signal data
        y.refi = rdi(1); % reference signal index
        y.chan = sch; % sensor channel idnexes
        y.zsens = sd; % batch and sample averaged transversal amplitude profile
        y.objval = norm(y.zsens(~isnan(y.zsens)),options.norm); % objective function value
        y.spec = spec; % auto-spectra
        y.freq = freq; % frequency vector
        y.sens = sens; % sensor sample data
        y.time = time; % time vector
        y.sch = options.sch; % valid sensor channel
        y.winfun = options.winfun;
    end
    function data = hexite(x,i,ac,m,l,p,b,dq)
        arguments (Input)
            x {mustBeVector} % actuator control vector
            i {mustBeVector} % actuator index
            ac {mustBeVector} % actuator calibration
            m mcu
            l lcard
            p function_handle % process handle
            b (1,1) {mustBeInteger,mustBePositive} % batch size
            dq (1,:) parallel.pool.DataQueue % send to data queue
        end
        arguments (Output)
            data (1,1) struct
        end
        xdata = cfic.hactuate(m,x,i,ac);
        xdata.action = x; xdata.channel = i;
        ydata = p(arrayfun(@(x)l.adcread(),1:b,'UniformOutput',false));
        data = struct(actuator=xdata,sensor=ydata);
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
    function [ft, ch] = calibrateSensor(data,n,ch,options)
        % %% example
        % folder = '\calibration';
        % data = loadlgraph(folder);
        % data.n = 120:5:200;
        % data.ch = [2:12,14:16,18:29,32];
        arguments (Input)
            data (:,:,:) % ADC data [channel × sample × rpm]
            n {mustBeVector} % wind tunnel rpm
            ch {mustBeVector,mustBeInteger,mustBePositive} % sensor channel
            options.extend (1,1) logical = true % extend to origin ADC channel size
            options.folder {mustBeFolder} % to save calibration
        end
        arguments (Output)
            ft (:,1) cell
            ch {mustBeVector}
        end
        u = 0.099*n;
        dudy = 0.2124*u.^1.591;
        s = squeeze(mean(data(ch,:,:),2));
        s = mat2cell(s,ones(1,size(s,1)),size(s,2));
        % fit
        ft = cellfun(@(x)fit(x(:),dudy(:),'poly2'),s,'UniformOutput',false);
        % show results: s(du/dy)
        f = figure('WindowStyle','docked'); t = tiledlayout(f);
        ax = nexttile(t); hold(ax,'on'); grid(ax,'on'); box(ax,'on'); axis(ax,'square');
        p = cellfun(@(s)plot(dudy,s,'-o','MarkerFaceColor','auto'),s);
        c = arrayfun(@(p)p.Color,p,'UniformOutput',false);
        cellfun(@(f,x,c)plot(f(x),x,'-s','MarkerFaceColor','auto','Color',c),ft,s,c)
        xlabel(ax,'du/dy, 1/s'); ylabel(ax,'$\bar{s}$, V','Interpreter','latex')
        l = legend(ax,num2str(ch(:)),'Location','eastoutside','NumColumns',2);
        title(l,'channel','FontWeight','normal')
        subtitle(string(datetime));
        % show results: du/dy(n)
        f = figure('WindowStyle','docked'); t = tiledlayout(f);
        ax = nexttile(t); hold(ax,'on'); grid(ax,'on'); box(ax,'on'); axis(ax,'square');
        cellfun(@(f,x)plot(ax,f(x),n,'-s','MarkerFaceColor','auto'),ft,s)
        xlabel(ax,'du/dy, 1/s'); ylabel(ax,'n, r/m')
        l = legend(num2str(ch(:)),'Location','eastoutside','NumColumns',2);
        title(l,'channel','FontWeight','normal')
        subtitle(string(datetime));
        % optional
        if options.extend
            ind = 1:size(data,1);
            temp = arrayfun(@(x)@(y)nan(numel(y),1),ind,'UniformOutput',false);
            temp(ch) = ft; ft = temp(:);
            ch = ind;
        end
        % save fit
        if isfield(options,'folder')
            filename = string(datetime('now','Format','yyyy-MM-dd HH-mm-ss'));
            filename = fullfile(options.folder,strcat(filename,'.mat'));
            save(filename,'ft','ch')
        end
    end
    function y = applySensorCalibration(ft,data)
        arguments (Input)
            ft (:,1) cell
            data (:,:) double %  [channel × sample]
        end
        arguments (Output)
            y (:,:) double
        end
        sz = size(data);
        y = cellfun(@(f,d)reshape(f(d),size(d)),ft(:),mat2cell(data,ones(1,sz(1)),sz(2)),'UniformOutput',false);
        y = squeeze(cat(ndims(y{1})+1,y{:}));
    end
    function result = modelWaveCancel(dist_resp,dist_amp,act_resp,act_amp,sim_dist_amp,sim_act_amp,ach,sch,options)
        arguments (Input)
            dist_resp {mustBeMatrix} % disturbance sensor responses [channel × amplitude]
            dist_amp {mustBeVector} % disturbace amplitude
            act_resp (:,:,:) % control disturbance sensor responses [sensor channel × actuator channel × amplitude]
            act_amp {mustBeVector}
            sim_dist_amp {mustBeVector} % disturbance amplitude at control
            sim_act_amp {mustBeVector} % actuator amplitude at control
            ach {mustBeVector} % actuator channel
            sch {mustBeVector} % sensor channel
            options.solver {mustBeMember(options.solver, {'linear-regression', 'fmincon', 'ga'})} = 'linear-regression'
            options.lb {mustBeVector}
            options.ub {mustBeVector}
            options.folder {mustBeFolder}
            options.norm {mustBeInteger,mustBePositive} = 2
        end
        arguments (Output)
            result (1,1) struct
        end
        function u = reval(f,a)
            u = cellfun(@(f,a)f(a),f(:),num2cell(a(:)),'UniformOutput',false);
            u = squeeze(sum(cat(ndims(u{1})+1,u{:}),ndims(u{1})+1,'omitmissing'));
        end
        
        % fit artificial disturbances
        [DAMP,SCH] = meshgrid(dist_amp,sch);
        tdfit = fit([SCH(:),DAMP(:)],dist_resp(:),'linearinterp');
        dist_fit = @(x)reshape(tdfit(sch,x*ones(1,numel(sch))),[],1);
        % select disturbance amplitude
        y = dist_fit(sim_dist_amp);
        coff = y;

        % fit control disturbances
        sz = size(act_resp);
        tafit = mat2cell(act_resp,sz(1),ones(1,sz(2)),sz(3));
        [AAMP,SCH] = meshgrid(act_amp,sch);
        tafit = cellfun(@(x)fit([SCH(:),AAMP(:)],x(:),'linearinterp'),tafit,'UniformOutput',false);
        fi = cellfun(@(f)@(x)reshape(f(sch,x*ones(1,numel(sch))),[],1),tafit,'UniformOutput',false);
        fsum = @(x)reval(fi,x);

        switch options.solver
            case 'linear-regression'
                x0 = sim_act_amp;
                P = cellfun(@(f,x)f(x),fi(:),num2cell(x0(:)),'UniformOutput',false);
                P = squeeze(cat(ndims(P{1})+1,P{:}));
                T = P*diag(1./x0);
                u = mldivide(T,-y);
                con = T*u+y;
            otherwise
                % define solver handle
                slvf = str2func(options.solver);
                % define problem
                problem = struct(solver = options.solver, A = [], b = [], Aeq = [], beq = []);
                problem.solver = options.solver;
                problem.x0 = sim_act_amp;
                if isfield(options,'lb'); problem.lb = options.lb; end
                if isfield(options,'ub'); problem.ub = options.ub; end
                objective = @(x)norm(fsum(x)+y,options.norm);
                % configure problem according to solver
                switch options.solver
                    case 'fmincon'
                        problem.objective = objective;
                        problem.options = optimoptions('fmincon','Algorithm','interior-point','PlotFcn',...
                            {@optimplotx, @optimplotfval, @optimplotfirstorderopt});
                    case 'ga'
                        problem.nvars = numel(ach);
                        problem.fitnessfcn = objective;
                        problem.options = optimoptions('ga','ConstraintTolerance',1e-6,...
                            'PlotFcn',{@gaplotbestf, @gaplotscores, @gaplotdistance});
                end
                % solve
                u = slvf(problem);
                con = fsum(u)+y;
        end

        % show disturbances
        f = figure('WindowStyle','docked','Name','approximation','NumberTitle','off');
        nexttile; hold on; box on; grid on;
        if exist('P','var')
            T = P*diag(1./x0).*u(:)';
        else
            P = cellfun(@(f,x)f(x),fi(:),num2cell(u(:)),'UniformOutput',false);
            P = squeeze(cat(ndims(P{1})+1,P{:}));
            T = P;
        end
        [ACH,SCH] = meshgrid(ach,sch);
        surf(SCH,ACH,T)
        xlabel('sensor channel'); ylabel('actuator channel');
        zlabel('amplitude'); view([320,70]);
        subtitle('control packets')

        % show control results
        f = figure('WindowStyle','docked','Name','simulation','NumberTitle','off');
        nexttile; hold on; box on; grid on; pbaspect([3,1,1]);
        plot(sch,coff,'-o','DisplayName','off','MarkerFaceColor','auto')
        plot(sch,con,'-s','DisplayName','on','MarkerFaceColor','auto')
        l = legend(); title(l,'control','FontWeight','normal')
        xlabel('channel'); ylabel('amplitude'); subtitle('sensor')
        nexttile; hold on; box on; grid on; pbaspect([3,1,1]);
        plot(ach,u,'-o')
        xlabel('channel'); ylabel('amplitude'); subtitle('actuator')
        % estimate norm
        n = options.norm; ncoff = norm(coff,n); ncon = norm(con,n);
        nlabel = sprintf("%s: n^{off}_{%d}=%.4f; n^{on}_{%d}=%.4f; n^{on}_{%d}/n^{off}_{%d}=%.4f",...
            options.solver,n,ncoff,n,ncon,n,n,ncon./ncoff);
        sgtitle(f,nlabel)

        result = struct(ach=ach,sch=sch,coff=coff,con=con,y=y,u=u,ncoff=ncoff,ncon=ncon,method=options.solver);
        if exist('problem','var'); result.problem = problem; end

        if isfield(options,'folder')
            filename = string(datetime('now','Format','yyyy-MM-dd HH-mm-ss'));
            filename = fullfile(options.folder,strcat(filename,'.mat'));
            save(filename,'result')
            fprintf('save results into %s\n',filename)
        end

    end
end
end