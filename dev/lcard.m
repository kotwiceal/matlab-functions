classdef lcard < handle
    properties (Access = public)
        device
        model {mustBeMember(model, {'e14-440'})} = 'e14-440'
        library {mustBeText} = 'MyCppLib'
        dqlog (1,1) parallel.pool.DataQueue
        adcpars % ADC parameters
        description % module description
        bios {mustBeText} = '' % bios filename
        adc struct = struct(channel=false(1,32),gain=zeros(1,32),... 
            difm=false(1,32),scale=ones(1,32),offset=zeros(1,32),...
            calz=false(1,32),rate=25,mask=1:32,pause=1,dquser=[],...
            resolution=2^14,range=20)
        dq struct % data queue
        ff struct % feval future
        figures struct
    end
    properties (Access = private)
        adcs struct = struct(buffer=[],dma=[]) % support ADC parameters
        dql (:,1) cell = {'log';'adcview'} % data queue label
        ffl (:,1) cell = {'asyncfileread';'asyncadcread'} % feval future label
        figl (:,1) cell = {'lcard'} % figure labels
        pool parallel.Pool
    end
    methods (Access = public)
        function obj = lcard(options,params)
            arguments (Input)
                options.model {mustBeMember(options.model, {'e14-440'})} = 'e14-440'
                options.library {mustBeText} = 'MyCppLib'
                options.bios {mustBeText} = ''
                params.dqlog (1,1) parallel.pool.DataQueue
                params.dquser (1,:) parallel.pool.DataQueue
            end
            % assign parameters
            for label = string(fieldnames(options))'; obj.(label) = options.(label); end
            % define data queues
            obj.dq = cell2struct(cellfun(@(x)parallel.pool.DataQueue,obj.dql,'UniformOutput',false),obj.dql);
            if isfield(params,'dqlog')
                obj.dq.log = params.dqlog;
            else
                if isempty(getCurrentWorker)
                    afterEach(obj.dq.log,@disp)
                end
            end
            if isempty(getCurrentWorker)
                afterEach(obj.dq.adcview,@obj.adcview)
            end
            % define feval future
            obj.ff = cell2struct(cellfun(@(x)parallel.FevalFuture,obj.ffl,'UniformOutput',false),obj.ffl);
            % define figures
            obj.figures = cell2struct(cellfun(@(x)figure('Name',x,'WindowStyle','docked','NumberTitle','off','Visible','off'),...
                obj.figl,'UniformOutput',false),obj.figl);
        end
        function initialize(obj)
            d = dbstack; flabel = sprintf("@%s:",d(1).name);
            % get device handle
            switch obj.model
                case 'e14-440'
                    obj.device = clib.(obj.library).GetILE440Instance();
                otherwise
                    me = sprintf("%s Device isn`t initialized",flabel);
                    if isempty(getCurrentWorker)
                        error(me)
                    else
                        send(obj.dq.log,strcat("Error. ",me));
                    end
            end

            % create USB session          
            for i= 0:127
                state = obj.device.OpenLDevice(i);
                if state
                    send(obj.dq.log,sprintf("%s Open device: %d",flabel,i));
                    break
                end   
            end
            if ~state
                me = sprintf("%s Device USB connection is failed",flabel);
                if isempty(getCurrentWorker)
                    warning(me)
                else
                    send(obj.dq.log,strcat("Warning. ",me));
                end
                return
            end

            % load module or upload bios
            if isempty(obj.bios)
                state = obj.device.LOAD_MODULE();
            else
                if isfile(obj.bios)
                    state = obj.device.LOAD_MODULE(options.bios);
                else
                    me = sprintf("%s %s isn`t file",flabel,options.bios);
                    if isempty(getCurrentWorker)
                        error(me)
                    else
                        send(obj.dq.log,strcat("Error. ",me));
                    end
                end
            end
            me = sprintf("%s Loading module: %d",flabel,state);
            send(obj.dq.log,me)
            if ~state; error(me); end
    
            % test module
            state = obj.device.TEST_MODULE();
            me = sprintf("%s Testing module: %d",flabel,state);
            send(obj.dq.log,me)
            if ~state; error(me); end

            % get module description
            switch obj.model
                case 'e14-440'
                    obj.description = clib.(obj.library).MODULE_DESCRIPTION_E440();
                    obj.device.GET_MODULE_DESCRIPTION(obj.description);
                otherwise
                    me = sprintf("%s Module description not retrieved",flabel);
                    if isempty(getCurrentWorker)
                        error(me)
                    else
                        send(obj.dq.log,strcat("Error. ",me));
                    end
            end
        end
        function state = release(obj)
            d = dbstack; flabel = sprintf("@%s:",d(1).name);
            if ~isempty(obj.device)
                try
                    state = obj.device.CloseLDevice();
                    send(obj.dq.log,sprintf("%s Close device: %d",flabel,state))
                    state = obj.device.ReleaseLInstance();
                    send(obj.dq.log,sprintf("%s Release instance: %d",flabel,state))
                    clibRelease(obj.device)
                catch
                    state = false;
                    me = sprintf("%s Release device is failed",flabel);
                    if isempty(getCurrentWorker)
                        warning(me)
                    else
                        send(obj.dq.log,strcat("Warning. ",me));
                    end
                end
            end
        end
        function adcconf(obj,params)
            % configure ADC: synchronize or assign parameters
            arguments (Input)
                obj
                params.rate (1,1) double = 400 % kHz
                params.channel (1,:) logical = true(1,32) % channel mask
                params.difm (1,:) logical = true(1,32) % enable differential mode
                params.calz (1,:) logical = false(1,32) % enable zero calibration
                params.gain (1,:) {mustBeInteger, mustBeInRange(params.gain,0,3)} = zeros(1,32)
                params.scale (1,:) double = ones(1,32)
                params.offset (1,:) double = zeros(1,32)
                params.mask (1,:) = 1:32 % channel mask
                params.pause (1,1) {mustBePositive} = 1
                params.dquser (1,:) parallel.pool.DataQueue
                params.resolution (1,1) {mustBeInteger,mustBePositive} = 2^14
                params.range (1,1) {mustBePositive} = 20
            end
            d = dbstack; flabel = sprintf("@%s:",d(1).name);
            send(obj.dq.log,sprintf("%s configure ADC",flabel));
            obj.device.STOP_ADC();
            switch obj.model
                case 'e14-440'
                    obj.adcpars = clib.(obj.library).ADC_PARS_E440();
                otherwise
                    me = sprintf("%s ADC configuration is failed",flabel);
                    if isempty(getCurrentWorker)
                        error(me)
                    else
                        send(obj.dq.log,strcat("Error. ",me));
                    end
            end
            % assign parameters
            for label = string(fieldnames(params))'; obj.adc.(label) = params.(label); end

            % retrieve ADC parameters
            obj.device.GET_ADC_PARS(obj.adcpars);

            % modify ADC control table
            lcard.elas(obj.adcpars.ControlTable,zeros(1,obj.adcpars.ControlTable.Dimensions, 'uint8'))
            channel = find(params.channel)-1;
            data = uint8(params.gain*64+double(params.difm)*32+channel);
            lcard.elas(obj.adcpars.ControlTable,data)

            % modify ADC parameters
            % obj.adcpars.IsAdcEnabled = true;
            obj.adcpars.AdcRate = params.rate;
            obj.adcpars.ChannelsQuantity = numel(channel);

            % set ADC parameters
            obj.device.SET_ADC_PARS(obj.adcpars);

            % define support parameters
            obj.adcs.buffer = clib.array.(obj.library).Short(obj.adcpars.AdcFifoLength);
            obj.adcs.dma = [obj.adcpars.AdcFifoBaseAddress,obj.adcpars.AdcFifoBaseAddress+obj.adcpars.AdcFifoLength];
            obj.adcs.nch = numel(find(obj.adcpars.ControlTable.uint8));
        end
        function data = adcread(obj,mode)
            arguments (Input)
                obj 
                mode {mustBeMember(mode, {'dram'})} = 'dram'
            end
            arguments (Output)
                data (:,:) double
            end
            d = dbstack; flabel = sprintf("@%s:",d(1).name);
            send(obj.dq.log,sprintf("%s read ADC",flabel));
            switch mode
                case 'dram'
                    obj.device.STOP_ADC();
                    obj.device.START_ADC();
                    pause(obj.adc.pause)
                    obj.device.GET_DM_ARRAY(obj.adcs.dma(1),obj.adcs.dma(2)/2,obj.adcs.buffer);
                    obj.device.STOP_ADC();
            end
            data = obj.adcs.buffer.double;
            data = reshape(data,obj.adcs.nch,[]);
            data = data(obj.adc.mask,:);
            data = data.*obj.adc.scale(:)+obj.adc.offset(:);
            data = data(:,1:fix(size(data,2)/2));
            data = data./obj.adc.resolution;
            data = data.*obj.adc.range./2.^(2*obj.adc.gain(:));
            arrayfun(@(dq)send(dq,data),[obj.dq.adcview,obj.adc.dquser]);
        end
        function res = status(obj)
            arguments (Input)
                obj 
            end
            arguments (Output)
                res
            end
             res = clib.(obj.library).LAST_ERROR_INFO_LUSBAPI();
             obj.device.GetLastErrorInfo(res);
        end
        function delete(obj)
            obj.release();
            structfun(@(x)cancel(x),obj.ff);
            structfun(@(x)delete(x),obj.dq)
        end
        function adcview(obj,data)
            arguments (Input)
                obj
                data (:,:) double
            end
            flabel = 'lcard';
            f = obj.figures.(flabel); 
            if ~isvalid(f)
                f = figure('Name',flabel,'WindowStyle','docked','NumberTitle','off');
                obj.figures.(flabel) = f; 
            end
            set(f,'Visible','on'); t = tiledlayout(f);
            delete(t.Children); ax = nexttile(t);
            cla(ax); hold(ax,'on'); box(ax,'on'); grid(ax,'on');
            plot(ax,data'); xlabel('sample'); ylabel('amplitude, V');
            channel = 1:size(data,1);
            l = legend(ax,string(num2str(channel(:))),'Location','eastoutside','NumColumns',2);
            title(l,'channel')
            subtitle(ax,string(datetime))
        end
        function loopadcread(obj,state,mode,options)
            arguments (Input)
                obj
                state (1,1) logical
                mode {mustBeMember(mode, {'sync', 'async'})}
                options.pause (1,1) {mustBePositive} = 1
            end
            if state
                cl = parallel.pool.Constant(obj);
                args = cat(2, {cl}, namedargs2cell(options));
                switch mode
                    case 'sync'
                        lcard.sloopadcread(args{:});
                    case 'async'
                        obj.release();
                        obj.ff.asyncadcread = parfeval(obj.pool,@lcard.sloopadcread,0,args{:});
                end
            else
                cancel(obj.ff.asyncadcread)
                obj.release();
                obj.initialize();
            end
        end
        function asyncadcread(obj,state,options)
            arguments (Input)
                obj
                state (1,1) logical
                options.pause (1,1) {mustBePositive} = 0.5
            end
            if state
                if isa(gcp('nocreate'),'parallel.ProcessPool')
                    obj.pool = gcp;
                else
                    delete(gcp('nocreate'))
                    obj.pool = parpool('Processes',2);
                end
                obj.release();
                cl = parallel.pool.Constant(obj);
                args = cat(2, {cl}, namedargs2cell(options));
                obj.ff.asyncadcread = parfeval(obj.pool,@lcard.sloopadcread,0,args{:});
            else
                cancel(obj.ff.asyncadcread)
                obj.release();
                obj.initialize();
            end
        end
        function asyncfileread(obj,folder,options)
            arguments
                obj
                folder {mustBeFolder}
                options.pause (1,1) {mustBePositive} = 0.01
                options.dq (1,:) parallel.pool.DataQueue = parallel.pool.DataQueue
                options.test (1,1) logical = false
            end
            options.dq = [options.dq, obj.dq.adcview];
            args = options;
            args.dq = [args.dq, obj.dq.adcview];
            args = namedargs2cell(args);
            args = cat(2,{folder},args);
            if options.test
                obj.ff.asyncfileread = parfeval(backgroundPool,@lcard.testloopfileread,0,'dq',options.dq);
            else
                obj.ff.asyncfileread = parfeval(backgroundPool,@lcard.loopfileread,0,args{:});
            end
        end
    end
    methods (Static, Access = private)
        function notifier(type,message,dq)
            arguments
                type {mustBeMember(type, {'wargning','error'})}
                message {mustBeText}
                dq parallel.pool.DataQueue = parallel.pool.DataQueue
            end
            if isempty(getCurrentWorker)
                send(dq,message);
            else
                func = str2func(type);
                func(message)
            end
        end
        function elas(arr1,arr2)
            % 1D array element-wise assignment
            for i = 1:numel(arr2)
                arr1(i) = arr2(i);
            end
        end
        function sloopadcread(c,options)
            arguments
                c parallel.pool.Constant
                options.pause (1,1) {mustBePositive} = 0.5
            end
            l = c.Value;
            if ~isa(l, 'lcard')
                error("`l` must be `lcard` class instance")
            end
            l.release();
            l.initialize();
            args = namedargs2cell(l.adc);
            l.adcconf(args{:});
            while 1
                pause(options.pause);
                l.adcread();
            end
        end
        function loopfileread(folder,options)
            arguments (Input)
                folder {mustBeFolder}
                options.dq (1,:) parallel.pool.DataQueue = parallel.pool.DataQueue
                options.pause (1,1) double = 0.01
            end
            dpattern = fullfile(folder,"*.dat"); % data pattern file
            ppattern = fullfile(folder,"*.par"); % parameters pattern file
            file0 = "";
            while 1
                pause(options.pause)
                dr = dir(dpattern);
                pr = dir(ppattern);
                if numel(dr) > 1
                    dr = dr(end-1);
                    pr = pr(end-1);
                    % list files
                    dfile = arrayfun(@(x)string(fullfile(x.folder,x.name)),dr);
                    pfile = arrayfun(@(x)string(fullfile(x.folder,x.name)),pr);
                    if ~strcmp(file0,dfile(end))
                        file0 = dfile(end);
                        % list datetime
                        dt = arrayfun(@(x)datetime(x.datenum,'ConvertFrom','datenum'),dr);
                        % read files
                        data = arrayfun(@(x)lgraphReadData(x),dfile,'UniformOutput',false);
                        param = arrayfun(@(x)lgraphReadParam(x),pfile,'UniformOutput',false);
                        % parse data
                        data = cellfun(@(d,p)reshape(d,p.RealChannelsQuantity,[]),data,param,'UniformOutput',false);
                        temp = cellfun(@(d,p)nan(numel(p.ActiveAdcChannelArray),size(d,2)),data,param,'UniformOutput',false);
                        for i = 1:numel(temp)
                            temp{i}(logical(param{i}.ActiveAdcChannelArray),:) = data{i};
                        end
                        data = temp;
                        % concatenate data
                        data = cat(ndims(data{1})+1,data{:});
                        % send to queue
                        if ~isempty(data); arrayfun(@(q)send(q,data),options.dq); end
                    end
                else
                    file0 = "";
                end
            end
        end
        function testloopfileread(options)
            arguments (Input)
                options.dq (1,:) parallel.pool.DataQueue = parallel.pool.DataQueue
                options.pause (1,1) double = 0.5
            end
            while 1
                pause(options.pause)

                p.n = 32; % channels
                p.m = 1024; % samples
                p.w = 5; % frequency
                p.k = 10; % periods
                p.d = 0; % noise
                p.s = 1; % shift
            
                a = sin(rescale(1:p.n,0,2*pi)); % amplitude
                q = (rand(1,1)-0.5)*pi; % phase
                t = linspace(0,1/p.w*p.k*(2*pi),p.m); % time
                x = a(:).*sin(p.w.*t+q)+rand(p.n,p.m)*p.d+p.s; % signal

                arrayfun(@(q)send(q,x),options.dq);
            end
        end
    end
end