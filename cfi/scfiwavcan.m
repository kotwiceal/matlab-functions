classdef scfiwavcan
    % Modelling of stationary cross-flow instability vorticity suppression by wave cancelation approach. 
    % Algorithm based on panoramic PIV measurements.
    properties
        xa (:,:) {mustBeA(xa, {'single', 'double'})} = []
        za (:,:) {mustBeA(za, {'single', 'double'})} = []
        srca (:,:,:,:) {mustBeA(srca, {'single', 'double'})} = []
        ampa (1,:) {mustBeA(ampa, {'single', 'double'})} = []
        xd (:,:) {mustBeA(xd, {'single', 'double'})} = []
        zd (:,:) {mustBeA(zd, {'single', 'double'})} = []
        srcd (:,:,:) {mustBeA(srcd, {'single', 'double'})} = []
        ampd (1,:) {mustBeA(ampd, {'single', 'double'})} = []
        rposa
        rposd
        rpospa
        rpospd
        wina
        wind
        respa
        respd
        xpa
        zpa
        xpd
        zpd
        profa
        profd
        fa % fit function of sum actuator weighed responses
        fai % fit function of each actuator weighed response
        fd % fit function of sum disturbance source responses (if it's multiple source)
        fdi % fit function of each disturbance source response (if it's multiple source)
        uc % optimization variables
        fc % objective evaluation at optimized variables
        ef % optimization exitflag
        ot % optimization output
        problem struct
    end

    properties (Hidden)
        cpr = []
        nch = []
        cnt = []
    end

    methods 
        function obj = scfiwavcan(xa,za,srca,ampa,xd,zd,srcd,ampd)
            arguments
                xa (:,:) {mustBeA(xa, {'single', 'double'})} = []
                za (:,:) {mustBeA(za, {'single', 'double'})} = []
                srca (:,:,:,:) {mustBeA(srca, {'single', 'double'})} = [] % size(srca)=[x,z,voltage,channel]
                ampa (1,:) {mustBeA(ampa, {'single', 'double'})} = []
                xd (:,:) {mustBeA(xd, {'single', 'double'})} = []
                zd (:,:) {mustBeA(zd, {'single', 'double'})} = []
                srcd (:,:,:) {mustBeA(srcd, {'single', 'double'})} = [] % size(srcd)=[x,z,amplitude]
                ampd (1,:) {mustBeA(ampd, {'single', 'double'})} = []
            end
            obj.xa = xa;
            obj.za = za;
            obj.srca = srca;
            obj.ampa = ampa;
            obj.xd = xd;
            obj.zd = zd;
            obj.srcd = srcd;
            obj.ampd = ampd;
            obj.nch = size(obj.srca,4);
        end

        function obj = drawroi(obj,type,options)
            arguments
                obj
                type {mustBeMember(type, {'packet-actuator', 'packet-disturbance', ...
                    'transverse-profile-actuator', 'transverse-profile-disturbance'})}
                options.index (1,1) double = 1
                options.levels (1,:) double = linspace(-1,1,50)
                options.clim (1,:) double = [-1,1]*0.2
                options.clabel {mustBeA(options.clabel, {'char', 'string'})} = '(u-u_{ref})/u_e'
            end
            switch type
                case 'packet-actuator'
                    x = obj.xa;
                    z = obj.za;
                    v = squeeze(obj.srca(:,:,options.index,:));
                    draw = 'drawpolygon';
                    rnumber = obj.nch;
                    rposition = obj.rposa;
                case 'packet-disturbance'
                    x = obj.xd;
                    z = obj.zd;
                    v = obj.srcd(:,:,options.index);
                    draw = 'drawpolygon';
                    rnumber = 1;
                    rposition = obj.rposd;
                case 'transverse-profile-actuator'
                    x = obj.xd;
                    z = obj.zd;
                    v = obj.srcd(:,:,options.index);
                    draw = 'drawrectangle';
                    rnumber = 1;
                    rposition = obj.rpospa;
                case 'transverse-profile-disturbance'
                    x = obj.xd;
                    z = obj.zd;
                    v = squeeze(obj.srca(:,:,options.index,:));
                    draw = 'drawrectangle';
                    rnumber = 1;
                    rposition = obj.rpospd;
            end
            obj.cpr = cellplot('contourf',x,z,v,...
                xlabel='x, mm',ylabel='z, mm',...
                colorbar='on',clabel=options.clabel,...
                axis='equal',...
                clim=options.clim,...
                levels=options.levels,...
                docked=true,...
                draw=draw,...
                rnumber=rnumber,...
                rfacealpha=0.1,...
                rposition=rposition,...
                rnumlabel='on',...
                ans='struct');
            obj.cnt = 1;
            obj.cpr.type = type;
        end

        function obj = nextroi(obj)
            ax = obj.cpr.axs; 
            arrayfun(@(a)set(a,'Visible','off'),ax.Children)
            c = flip(findobj(ax,'type','contour'));
            r = flip(findobj(ax,'type','images.roi.Polygon'));
            if obj.cnt == obj.nch
                obj.cnt = 1;
            end
            c(obj.cnt).Visible='on';
            r(obj.cnt).Visible='on';
            if obj.cnt <= obj.nch
                obj.cnt = obj.cnt + 1;
            end
        end

        function obj = setroi(obj,optpack,optprof)
            arguments
                obj 
                optpack.window {mustBeMember(optpack.window, {'none', 'tukeywin'})} = 'tukeywin' % enable weight by tukeywin 
                optpack.winfactor (1,1) double = 0.75 % tukeywin scale factor
                optpack.filt {mustBeMember(optpack.filt, {'none', 'gaussian'})} = 'gaussian'
                optpack.filtker (1,:) double = [4, 4]
                optpack.filtkerparam (1,1) double = 0.2
                optprof.isflip (1,1) logical = true
            end
            r = obj.cpr.resfunc();
            switch obj.cpr.type
                case 'packet-actuator'
                    obj.rposa = r.rgpos;
                    arg = namedargs2cell(optpack);
                    [obj.respa, obj.wina] = sliceWeightPackets(obj.xa,obj.za,obj.srca,obj.rposa,arg{:});
                case 'packet-disturbance'
                    obj.rposd = r.rgpos;
                    arg = namedargs2cell(optpack);
                    [obj.respd, obj.wind] = sliceWeightPackets(obj.xd,obj.zd,obj.srcd,obj.rposd,arg{:});
                case 'transverse-profile-actuator'
                    obj.rpospa = r.rgpos;
                    arg = namedargs2cell(optprof);
                    [obj.profa,obj.fa,obj.fai,obj.xpa,obj.zpa] = sliceFitProfiles(obj.xa,obj.za,obj.respa,obj.rpospa,obj.ampa,arg{:});
                case 'transverse-profile-disturbance'
                    obj.rpospd = r.rgpos;
                    arg = namedargs2cell(optprof);
                    [obj.profd,obj.fd,obj.fdi,obj.xpd,obj.zpd] = sliceFitProfiles(obj.xd,obj.zd,obj.respd,obj.rpospd,obj.ampd,arg{:});
            end
        end

        function obj = control(obj,x0,lb,ub,n,ampd,param,options)
            arguments
                obj
                x0 (1,:) double % initial approximation
                lb (1,:) double % lower boundary
                ub (1,:) double % upper boundary
                n (1,1) double % norm order
                ampd (1,1) double % disturbance packet amplitude
                param.solver {mustBeMember(param.solver, {'fmincon', 'ga'})} = 'fmincon'
                options.FiniteDifferenceType {mustBeMember(options.FiniteDifferenceType, {'forward', 'central'})} = 'forward'
                options.ConstraintTolerance (1,1) double = 1e-3
                options.MaxIterations (1,1) {mustBeInteger} = 10000
                options.DiffMinChange (1,1) double = 0.005
                options.DiffMaxChange (1,1) double = 0.5
                options.StepTolerance (1,1) double = 1e-6
                options.MaxFunctionEvaluations (1,1) {mustBeInteger} = 2000
            end

            slvf = str2func(param.solver);

            obj.problem = struct(solver = param.solver, A = [], b = [], Aeq = [], beq = []);
            obj.problem.solver = param.solver;
            obj.problem.x0 = x0;
            obj.problem.lb = lb;
            obj.problem.ub = ub;
            objective = @(x)norm(obj.fa(x)+obj.fd(ampd),n);
            
            switch param.solver
                case 'fmincon'
                    obj.problem.objective = objective;
                    arg = namedargs2cell(options);
                    obj.problem.options = optimoptions('fmincon','Algorithm','interior-point','PlotFcn',...
                        {@optimplotx, @optimplotfval, @optimplotfirstorderopt});
                case 'ga'
                    obj.problem.nvars = obj.nch;
                    obj.problem.fitnessfcn = objective;
                    obj.problem.options = optimoptions('ga','ConstraintTolerance',1e-6,...
                        'PlotFcn',{@gaplotbestf, @gaplotscores, @gaplotdistance});
            end
            [obj.uc, obj.fc, obj.ef, obj.ot] = slvf(obj.problem);
            nref = norm(obj.fd(ampd),n);
            nopt = objective(obj.uc);
            obj.showresult(ampd,n,nref,nopt);
        end

        function showresult(obj,ampd,n,nref,nopt)
            arguments
                obj
                ampd
                n
                nref
                nopt
            end
            xposlab = sprintf("x=%.1fmm",obj.xpa(1));
            nlab = sprintf("n^{no opt.}_{%d}=%.4f; n^{opt.}_{%d}=%.4f; n^{opt.}_{%d}/n^{no opt.}_{%d}=%.4f;",...
                n,nref,n,nopt,n,n,nopt./nref);

            cellplot('plot',obj.zpd,cat(2,obj.fd(ampd),obj.fd(ampd)+obj.fa(obj.uc)),...
                xlabel='z, mm',ylabel='(u-u_{ref})/u_e',...
                subtitle=xposlab,title=nlab,...
                legend='on',lstring={["no opt.","opt."]},docked=true)

            x = cat(1,obj.problem.lb,obj.problem.ub,obj.problem.x0,obj.uc)';
            cellplot('plot',x,xlabel='channel',ylabel='amplitude',...
                legend='on',lstring={["lb","ub","x0","x"]},docked=true,...
                subtitle=xposlab,title=nlab);
        end

        function s = exportroi(obj,varname)
            arguments (Input)
                obj 
                varname {mustBeMember(varname, {'rposa', 'rposd', 'rpospa', 'rpospd'})}
            end
            arguments (Output)
                s string
            end
            s = strcat(varname,"={{",join(cellfun(@(x)string(mat2str(x)),obj.(varname){1}),newline),"}}");
        end
    end
end

function [data, win] = sliceWeightPackets(x,z,data,rpos,options)
    arguments (Input)
        x (:,:) {mustBeA(x, {'single', 'double'})}
        z (:,:) {mustBeA(z, {'single', 'double'})}
        data (:,:,:,:) {mustBeA(data, {'single', 'double'})}
        rpos (1,1) cell
        options.window {mustBeMember(options.window, {'none', 'tukeywin'})} = 'tukeywin' % enable weight by tukeywin 
        options.winfactor (1,1) double = 0.75 % tukeywin scale factor
        options.filt {mustBeMember(options.filt, {'none', 'gaussian'})} = 'gaussian'
        options.filtker (1,:) double = [4, 4]
        options.filtkerparam (1,1) double = 0.2
    end
    arguments (Output)
        data (:,:,:,:) {mustBeA(data, {'single', 'double'})}
        win (:,:,:,:) {mustBeA(win, {'single', 'double'})}
    end
    switch options.filt
        case 'gaussian'
            data = imfilter(data,fspecial(options.filt,options.filtker,options.filtkerparam),'symmetric');
    end
    arg = num2cell(size(data));
    if ndims(data) == 4; arg{end} = ones(1,arg{end}); end
    data = squeeze(mat2cell(data,arg{:}));
    % slice data
    data = cellfun(@(p,d)maskcutdata(p,x,z,d,dims=[1,2],fill='outnan',shape='trim'),...
        rpos{1},data,'UniformOutput',false);
    data = cat(ndims(data{1})+1,data{:});
    % weight data
    win = [];
    switch options.window
        case 'tukeywin'
            ni = ~isnan(data);
            sz = size(data);
            for i = 1:prod(sz(2:end))
                win(:,i) = zeros(1,numel(data(:,i)));
                ind = find(ni(:,i));
                win(ind,i) = tukeywin(numel(ind),options.winfactor);
            end
            data(~ni) = 0;
            win = reshape(win,sz);
            data = data.*win;
        otherwise
            data(isnan(data)) = 0;
    end
end

function [data,f,fi,x,z] = sliceFitProfiles(x,z,data,rpos,amp,options)
    arguments (Input)
        x (:,:) {mustBeA(x, {'single', 'double'})}
        z (:,:) {mustBeA(z, {'single', 'double'})}
        data (:,:,:,:) {mustBeA(data, {'single', 'double'})}
        rpos (1,1) cell
        amp (1,:) {mustBeA(amp, {'single', 'double'})}
        options.isflip (1,1) logical % enable fit in range [-flip(amp),amp] (concatenate inverse packets)
    end
    arguments (Output)
        data (:,:,:) {mustBeA(data, {'single', 'double'})}
        f (1,1) function_handle
        fi (:,1) {mustBeA(fi, {'function_handle', 'cell'})}
        x (:,1) {mustBeA(x, {'single', 'double'})}
        z (:,1) {mustBeA(z, {'single', 'double'})}
    end
    % slice data
    [data,x,z] = maskcutdata(rpos{1}{1},x,z,data,dims=[1,2],...
        fill='none',shape='bounds',isrectangle=true);
    % averaging along x-axis dimension
    x = mean(x,2); z = mean(z,2); data = squeeze(mean(data,2));
    % linear piecewise fit of transverse profiles dependent on amplitude
    if options.isflip
        amp = [-flip(amp),amp];
        data = cat(2,-flip(data,2),data);
    end
    arg = num2cell(size(data));
    if ndims(data) == 3; arg{end} = ones(1,arg{end}); end
    [A, Z] = meshgrid(amp, z);
    fi = cellfun(@(v) fit([Z(:), A(:)], v(:), 'linearinterp'), ...
        squeeze(mat2cell(data,arg{:})), 'UniformOutput', false);
    fi = cellfun(@(f) @(a) f(z, a*ones(numel(z),1)), fi, 'UniformOutput', false);
    f = @(a) evalresp(fi,a);
end

function u = evalresp(f,a)
    arguments (Input)
        f (1,:) cell
        a (1,:) double
    end
    arguments (Output)
        u (:,1) double
    end
    u = cellfun(@(f,a)f(a),f,num2cell(a),'UniformOutput',false);
    u = mean(cat(2,u{:}),ndims(u{1}),'omitmissing');
end