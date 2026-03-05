classdef cfic < handle
    properties (Access = public)
        lcard_folder {mustBeText} = ""
        lcard_adc_nch (1,1) {mustBeInteger} = 32
        lcard_adc_zero (1,32) double
        lcard_adc_scale (1,32) double = repelem(0.001250,32);
        lcard_adc_offset (1,32) double
        lcard_adc_value (32,:) double

        mcu_dac_value (1,32) double
        mcu_dac_offset (1,32) double
        mcu_adc_offset (1,1) double
        mcu_address {mustBeText} = "10.10.1.1"
        mcu_port {mustBeInteger} = 8090
        mcu_com_get {mustBeText} = "get-param"
        mcu_com_set {mustBeText} = "set-param"
        mcu_url_set_param
        mcu_url_get_param

        figures struct = struct(d=[])
        tiles struct = struct(d=[])

        sdata
        pdata
        chmask (1,:) = 1:32
        ch_mask_adc (1,:) = 1:32
        ch_mask_dac (1,:) = 1:32

        dashboard
        result
    end
    properties (Access = public)
        %% parallel
        dql (:,1) cell = {'log';'dataview';'process';'processview';'asyncfileread';'httppost';'mcuget';'terminate';'progress';'result'} % data queue label
        dq % data queue
        ffl (:,1) cell = {'asyncfileread';'process';'optimize'} % feval future label
        ff % feval future
        pdql (:,1) cell = {'process';'httppost'} % pollable data queue label
        pdq  % pollable data queues
    end
    methods (Access = public)
        function  obj = cfic(lcard_folder)
            arguments (Input)
                lcard_folder {mustBeFolder}
            end
            obj.lcard_folder = lcard_folder;
            n = 32;
            obj.lcard_adc_zero = zeros(1,n);
            obj.lcard_adc_scale = repelem(0.001250,n);
            obj.lcard_adc_offset = zeros(1,n);

            obj.mcu_url_set_param = sprintf("http://%s:%d/%s",obj.mcu_address,obj.mcu_port,obj.mcu_com_set);
            obj.mcu_url_get_param = sprintf("http://%s:%d/%s",obj.mcu_address,obj.mcu_port,obj.mcu_com_get);

            % define data queues
            obj.dq = cellfun(@(x)parallel.pool.DataQueue,obj.dql,'UniformOutput',false);
            obj.dq = cell2struct(obj.dq,obj.dql);

            % define pollable data queues
            obj.pdq = cellfun(@(x)parallel.pool.PollableDataQueue(Destination="any"),obj.pdql,'UniformOutput',false);
            obj.pdq = cell2struct(obj.pdq,obj.pdql);

            % define handlers
            afterEach(obj.dq.log,@(x)fprintf("%s %s\n",datetime,x))
            afterEach(obj.dq.mcuget,@obj.mcuview)
            afterEach(obj.dq.terminate,@obj.terminate)
            afterEach(obj.dq.progress,@obj.optprogress)

            obj.dashboard.optimization = [];
            obj.result.optimization = [];

            afterEach(obj.dq.result,@obj.getresult)
        end

        function getresult(obj,x)
            obj.result.optimization = x;
        end

        function asyncfileread(obj,state,options)
            arguments
                obj 
                state (1,1) logical
                options.rmdir (1,1) logical = false
                options.test (1,1) logical = false
            end
            if state
                if options.rmdir
                    try
                        folder = obj.lcard_folder;
                        rmdir(folder,'s')
                        send(obj.dq.log,sprintf("remove `%s` directory",folder))
                    catch ex
                        warning(ex.message)
                    end
                end
                obj.dq.asyncfileread = parallel.pool.DataQueue;
                afterEach(obj.dq.asyncfileread, @obj.stack)
    
                obj.dq.preview = parallel.pool.DataQueue;
                afterEach(obj.dq.preview, @obj.preview)
    
                obj.dq.process = parallel.pool.DataQueue;
                afterEach(obj.dq.process, @obj.processed)
    
                obj.dq.processview = parallel.pool.DataQueue;
                afterEach(obj.dq.processview, @obj.processview)
    
                arg = struct(zero=obj.lcard_adc_zero,scale=obj.lcard_adc_scale,...
                    offset=obj.lcard_adc_offset,dq=[obj.dq.asyncfileread,obj.dq.preview]);
                arg = namedargs2cell(arg);

                try
                    cancel(obj.ff.asyncfileread)
                catch
                end

                if options.test
                    obj.ff.asyncfileread = parfeval(backgroundPool,@loop,0,'dq',[obj.dq.asyncfileread,obj.dq.preview]);
                else
                    obj.ff.asyncfileread = parfeval(backgroundPool,@cfic.lcardLoopLoad,0,...
                       obj.lcard_folder,obj.lcard_adc_nch,arg{:});
                end
                
                send(obj.dq.log,"start loop asynchronous file reading")
            else
                cancel(obj.ff.asyncfileread)
                send(obj.dq.log,"stop loop asynchronous file reading")
            end
        end

        function optimize(obj,problem,index)
            arguments
                obj 
                problem (1,1) struct
                index {mustBeVector}
            end
            urlset = obj.mcu_url_set_param;
            urlget = obj.mcu_url_get_param;
            dqlog = obj.dq.log;
            dqget = obj.dq.mcuget;
            func = @(x)cfic.mcu_set_get(urlget,urlset,struct(dac=struct(value=x,index=index)),...
                dqlog,dqget,parallel.pool.PollableDataQueue);
            args = {problem,func,obj.dq.log,obj.dq.terminate,obj.dq.progress,obj.dq.result,obj.pdq.process};
            obj.ff.optimize = parfeval(backgroundPool,@cfic.optimization,0,args{:});
        end

        function delete(obj)
            structfun(@(x)cancel(x),obj.ff)
            structfun(@(x)delete(x),obj.dq)
            structfun(@(x)delete(x),obj.pdq)
        end

        function data = mcu_get(obj)
            arguments (Input)
                obj 
            end
            arguments (Output)
                data (1,1) struct
            end
            data = cfic.http_get(obj.mcu_url_get_param,obj.dq.log,obj.dq.mcuget);
        end
        function state = mcu_set(obj,data)
            arguments (Input)
                obj 
                data (1,1) struct
            end
            arguments (Output)
                state (1,1) logical
            end
            state = cfic.http_post(obj.mcu_url_set_param,data,obj.dq.log,obj.pdq.httppost);
            cfic.http_get(obj.mcu_url_get_param,obj.dq.log,obj.dq.mcuget);
        end
    end
    methods (Access = public)
    %% parallel handlers
    function stack(obj,fdata)
        arguments
            obj 
            fdata (1,1) struct
        end
        % send(obj.dq.log,"asynchronous file reading is completed")
        obj.sdata = fdata;
        obj.lcard_adc_value = fdata.data;
        dqh = obj.dq.process;
        obj.ff.process = parfeval(backgroundPool,@(x)send(dqh,cfic.process(x)),0,fdata);
    end
    function processed(obj,x)
        arguments
            obj
            x (1,1) struct
        end
        obj.pdata = x;
        send(obj.dq.processview,x)
        send(obj.pdq.process,x)
    end
    function terminate(obj,state)
        if state
            cancel(obj.ff.optimize)
            send(obj.dq.log,"optimization is terminated")
        end
    end
    end
    methods (Access = public)
    %% visualization handlers
    function preview(obj,x)
        arguments
            obj 
            x (1,1) struct
        end
        mask = obj.ch_mask_adc;
        data = x.data(mask,:)';

        label = 'dataview';
        obj.figure(label);
        t = tiledlayout(obj.figures.(label));
        delete(t.Children)
        ax = nexttile(t); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
        plot(ax,data);
        xlabel('samples'); ylabel('values');
        legend(ax,string(num2str(obj.chmask(:))),'Location','east')
        title(ax,string(x.datetime))
    end
    function processview(obj,x)
        arguments
            obj 
            x (1,1) struct
        end
        label = 'process';
        obj.figure(label);
        t = tiledlayout(obj.figures.(label));
        delete(t.Children)
        ax = nexttile(t); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
        plot(ax,obj.chmask,x.ymean(obj.chmask));
        xlabel(ax,'channel'); ylabel(ax,'');
        title(ax,string(x.datetime))
    end
    function mcuview(obj,data)
        arguments
            obj 
            data (1,1) struct
        end
        mask = obj.ch_mask_dac;
        amp = data.dac.value(mask);
        offset = data.dac_offset.value;

        label = 'mcu';
        obj.figure(label);
        t = tiledlayout(obj.figures.(label));
        delete(t.Children)
        ax = nexttile(t); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
        bar(amp); xlabel('channel'); ylabel('amplitude');
        ax = nexttile(t); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
        bar(offset); xlabel('channel'); ylabel('offset');
    end
    function optprogress(obj,data)
        arguments
            obj 
            data (1,1) struct
        end
        l = 4;
        obj.dashboard.optimization = cat(1,obj.dashboard.optimization,data);
        n = numel(obj.dashboard.optimization);
        if n > 4
            m = (n-l+1):n;
        else
            m = 1:n;
        end
        xdata = arrayfun(@(x)x.xdata.dac.value,obj.dashboard.optimization,'UniformOutput',false);
        xdata = cat(2,xdata{:}); xdata = xdata(obj.ch_mask_dac,m);
        ydata = arrayfun(@(x)x.ydata.ymean,obj.dashboard.optimization,'UniformOutput',false);
        ydata = cat(2,ydata{:}); ydata = ydata(obj.ch_mask_adc,m);

        ynorm = arrayfun(@(x)x.ydata.ynorm,obj.dashboard.optimization);

        label = 'opt';
        obj.figure(label);
        t = tiledlayout(obj.figures.(label));
        if isempty(t.Children)
            arrayfun(@(x)set(nexttile(t),'Box','on','XGrid','on','YGrid','on'),1:3)
            arrayfun(@(x)hold(x,'on'),t.Children)
        end
        axs = flip(findobj(t,'type','Axes'));
        arrayfun(@(x)cla(x),axs);

        ax = axs(1); colors = colororder;
        p = plot(ax,xdata,'-o','Color',colors(1,:),'MarkerFaceColor','auto');
        xlabel(ax,'channel'); ylabel(ax,'amplitude')
        arrayfun(@(p,c)set(p,'Color',[p.Color,c]),p,linspace(0.25,1,numel(p))')
        subtitle(ax,'actuator'); legend(ax,split(num2str(m)),'Location','southeast')

        ax = axs(2); colors = colororder;
        p = plot(ax,ydata,'.-','Color',colors(1,:),'MarkerFaceColor','auto');
        xlabel(ax,'channel'); ylabel(ax,'amplitude')
        arrayfun(@(p,c)set(p,'Color',[p.Color,c]),p,linspace(0.25,1,numel(p))')
        subtitle(ax,'sensor'); legend(ax,split(num2str(m)),'Location','southeast')

        ax = axs(3);
        plot(ax,ynorm,'-o','MarkerFaceColor','auto')
        yline(ax,ynorm(1),'-','reference'); xlabel('iteration'); ylabel('objective function')
    end
    end
    methods (Access = public)
    %% support handlers
    function figure(obj,label)
        arguments
            obj 
            label {mustBeText}
        end
        if isfield(obj.figures,label)
            f = obj.figures.(label);
            if ~isvalid(f)
                f = figure('Name',label,'WindowStyle','docked','NumberTitle','off');
            end
        else
            f = figure('Name',label,'WindowStyle','docked','NumberTitle','off');
        end
        if isempty(f.Children)
            obj.tiles.(label) = tiledlayout(f);
        end
        obj.figures.(label) = f;
    end
    end
    methods (Static)
    %% static handlers

    % MCU handlers
    function data = http_get(url,dqlog,dqget)
        arguments (Input)
            url {mustBeText}
            dqlog (1,1) parallel.pool.DataQueue
            dqget (1,1) parallel.pool.DataQueue
        end
        arguments (Output)
            data (1,:) struct
        end
        data = struct([]);
        d = dbstack; flabel = sprintf("@%s:",d(1).name);
        try
            request = matlab.net.http.RequestMessage;
            response = request.send(url);
            data = response.Body.Data;
            send(dqget,data);
            send(dqlog,sprintf("%s HTTP GET request: %s",flabel,jsonencode(data)));
        catch ex
            send(dqlog,sprintf("%s HTTP GET request failed: %s",flabel,ex.message));
        end
    end
    function state = http_post(url,data,dqlog,pdqpost)
        arguments (Input)
            url {mustBeText} 
            data (1,1) struct
            dqlog (1,1) parallel.pool.DataQueue
            pdqpost (1,1) parallel.pool.PollableDataQueue
        end
        arguments (Output)
            state (1,1) logical
        end
        d = dbstack; flabel = sprintf("@%s:",d(1).name);
        state = false;
        try
            data = jsonencode(data);
            request = matlab.net.http.RequestMessage('POST', ...
                [matlab.net.http.field.ContentTypeField('application/json'), ...
                matlab.net.http.field.AcceptField('application/json')], data);
            request.send(url);
            send(dqlog, sprintf("%s HTTP POST request: %s",flabel,data));
            state = true;
        catch ex
            send(dqlog,sprintf("%s HTTP POST request failed: %s",flabel,ex.message));
        end
        send(pdqpost,state);
    end
    function odata = mcu_set_get(urlget,urlset,idata,dqlog,dqget,pdqpost)
        arguments (Input)
            urlget (1,1) {mustBeText}
            urlset (1,1) {mustBeText}
            idata (1,1) struct
            dqlog (1,1) parallel.pool.DataQueue
            dqget (1,1) parallel.pool.DataQueue
            pdqpost (1,1) parallel.pool.PollableDataQueue
        end
        arguments (Output)
            odata (1,1) struct
        end
        d = dbstack; flabel = sprintf("@%s:",d(1).name);
        odata = struct([]);
        try
            cfic.http_post(urlset,idata,dqlog,pdqpost);
            odata = cfic.http_get(urlget,dqlog,dqget);
            send(dqlog, sprintf("%s HTTP POST/GET request",flabel));
        catch ex
            send(dqlog,sprintf("%s HTTP POST/GET request failed: %s",flabel,ex.message));
        end
    end
    function d = process(d)
        arguments (Input)
           d (1,1) struct
        end
        arguments (Output)
            d (1,1) struct
        end
        % y - ADC signal
        d.ymean = mean(d.data,2);
        d.ynorm = norm(d.ymean,2);

        % y = struct;
        % y.x = x.data;
        % y.xm = mean(y.x,2);
        % y.y = norm(y.xm,2);
        % s = 0;
        % sz = size(x);
        % arg = arrayfun(@(x)ones(1,x),sz,'UniformOutput',false);
        % arg{2} = sz(2);
        % xc = squeeze(mat2cell(x,arg{:}));
        % ind = cellfun(@(x)find(islocalmax(x,2))+s,xc,'UniformOutput',false);
        % xm = cellfun(@(x,i)mean(x(i),'all'),xc,ind);
        % y = struct;
        % y.x = x;
        % y.ind = ind;
        % y.xm = xm;
        % y.y = norm(y.xm,2);
    end
    function y = hsync(func,x,dqlog,dqterminate,cprocess,dqprogress,options)
        %% handle of action and response synchronization
        arguments (Input)
            func (1,1) function_handle % actuator control handle
            x {mustBeVector} % actuator control vector
            dqlog (1,1) parallel.pool.DataQueue % to log
            dqterminate (1,1) parallel.pool.DataQueue % to terminate execution  
            cprocess (1,1) parallel.pool.PollableDataQueue % to poll data from async worker
            dqprogress (1,1) parallel.pool.DataQueue % send to another worker
            options.duration (1,1) double = 2
            options.datafail (1,1) {mustBeInteger} = 4
            options.timeout (1,1) double = 60
        end
        arguments (Output)
            y (1,1) struct
        end
        d = dbstack; flabel = sprintf("@%s:",d(1).name);
        xdata = func(x);
        pause(0.25)
        % todo: send lock to sync
        if ~isempty(xdata)
            wstate = true;
            dt = datetime;
            while wstate
                [ydata, dstate] = poll(cprocess,options.timeout);
                if dstate
                    if (ydata.datetime-dt)>seconds(options.duration)
                        wstate = false;
                    else
                        % send(dqlog,sprintf("%s criteria doesn`t fullfil",flabel));
                    end
                else
                    options.datafail = options.datafail - 1;
                    send(dqlog,sprintf("%s poll `process` is failed, try again, %d attempt(s) left",flabel,options.datafail));
                end
                if options.datafail == 0
                    send(dqlog,sprintf("%s poll `process` is failed, terminate optimization",flabel));
                    send(dqterminate,true);
                end
            end
            y = ydata;
            send(dqprogress,struct(xdata=xdata,ydata=ydata));
            send(dqlog,sprintf("%s data are polled",flabel));
        else
            send(dqlog,sprintf("%s MCU HTTP POST request is failed, terminate optimization",flabel));
            send(dqterminate,true);
        end
    end

    function optimization(problem,func,dqlog,dqterminate,dqprogress,dqresult,cprocess)
        arguments
            problem (1,1) struct
            func (1,1) function_handle
            dqlog (1,1) parallel.pool.DataQueue % to log
            dqterminate (1,1) parallel.pool.DataQueue % to terminate execution
            dqprogress (1,1) parallel.pool.DataQueue % to visualize progress
            dqresult (1,1) parallel.pool.DataQueue % to send result to main worker
            cprocess (1,1) parallel.pool.PollableDataQueue % to poll data from async worker
        end
        d = dbstack; flabel = sprintf("@%s:",d(1).name);
        try
            hfunc = @(x)cfic.hsync(func,x,dqlog,dqterminate,cprocess,dqprogress);
            fobj = @(x)getfield(hfunc(x),'ynorm'); % objective function
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
            hfunc(zeros(numel(problem.x0),1));
            
            lab = {'x';'fval';'exitflag';'output'}; result = cell(numel(lab),1);
            send(dqlog,sprintf("%s start optimization",flabel))
            [result{:}] = method(problem);
            result = cell2struct(result,lab);
            send(dqlog,sprintf("%s optimization is completed",flabel))

            send(dqlog,sprintf("%s evaluate optimal state",flabel))
            hfunc(result.x);

            send(dqlog,sprintf("%s optimization is finished",flabel))
            send(dqresult,result)
        catch ex
            send(dqlog,sprintf("%s optimization if failed: %s",flabel,ex.message))
            send(dqterminate,true);
        end
    end
    function data = lcardReadFile(filename,options)
    arguments (Input)
        filename {mustBeFile}
        options.cast {mustBeMember(options.cast, {'single', 'double'})} = 'double'
    end
    arguments (Output)
        data (:,1) {mustBeA(data, {'single', 'double'})}
    end
        fid = fopen(filename, 'r');
        data = fread(fid, 'int16');
        data = cast(data, options.cast);
        fclose(fid);
    end
    function lcardLoopLoad(folder,nchans,options)
        arguments (Input)
            folder {mustBeFolder}
            nchans (1,1) {mustBeInteger}
            options.zero (1,:) {mustBeA(options.zero, {'single', 'double'})} = zeros(1,nchans)
            options.scale (1,:) {mustBeA(options.scale, {'single', 'double'})} = repelem(0.001250,nchans)
            options.offset (1,:) {mustBeA(options.offset, {'single', 'double'})} = zeros(1,nchans)
            options.prelast (1,1) logical = true
            options.dq (1,:) parallel.pool.DataQueue = parallel.pool.DataQueue
            options.pause (1,1) double = 0.01
        end
        pattern = fullfile(folder,"*.dat");
        file0 = "";
        while 1
            pause(options.pause)
            dr = dir(pattern);
            if numel(dr) > 1
                dr = dr(end-1);
                % list files
                file = arrayfun(@(x)string(fullfile(x.folder,x.name)),dr);
                if ~strcmp(file0,file(end))
                    file0 = file(end);
                    % list datetime
                    dt = arrayfun(@(x)datetime(x.datenum,'ConvertFrom','datenum'),dr);
                    % read files
                    data = arrayfun(@(x)cfic.lcardReadFile(x),file,'UniformOutput',false);
                    % parse data
                    data = cellfun(@(x)reshape(x,nchans,[]),data,'UniformOutput',false);
                    % apply calibration
                    data = cellfun(@(x)(x+options.zero(:)).*options.scale(:)+options.offset(:),data,'UniformOutput',false);
                    % concatenate data
                    data = cat(ndims(data{1})+1,data{:});
                    if ~isempty(data)
                        arrayfun(@(x)send(x,struct(file=file,datetime=dt,data=data)),options.dq)
                    end
                end
            else
                file0 = "";
            end
        end
    end
    end
end

function [x, t] = genHotFilm(p)
arguments
    p.n (1,1) {mustBeInteger} = 32 % channels
    p.m = 1024; % samples
    p.w = 100; % frequency
    p.k = 10; % periods
    p.d = 0; % noise
    p.s = 1; % shift
end
    a = rand(p.n,1); % amplitude
    q = (rand(1,1)-0.5)*pi; % phase
    t = linspace(0,1/p.w*p.k*(2*pi),p.m); % time
    x = a.*sin(p.w.*t+q)+rand(p.n,p.m)*p.d+p.s; % signal
end

function loop(options)
    arguments
        options.pause (1,1) double = 1
        options.dq (1,:) parallel.pool.DataQueue = parallel.pool.DataQueue
    end
    while 1
        pause(options.pause);
        data = genHotFilm();
        arrayfun(@(x)send(x,struct(file="",datetime=datetime,data=data)),options.dq)
    end
end