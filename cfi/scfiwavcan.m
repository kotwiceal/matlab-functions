classdef scfiwavcan < handle
    % Modelling of stationary cross-flow instability vorticity suppression by wave cancelation approach. 
    % Algorithm based on panoramic PIV measurements.
    properties
        actuator struct
        disturbance struct
        result struct
    end

    properties (Hidden)
        cnt
        guip
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
            template = struct(x=[],z=[],src=[],amp=[],rpos=struct(packet=[],profile=[]),nch=[]);
            obj.actuator = template;
            obj.disturbance = template;

            obj.actuator.x = xa;
            obj.actuator.z = za;
            obj.actuator.src = srca;
            obj.actuator.amp = ampa;
            obj.actuator.nch = size(obj.actuator.src,4);

            obj.disturbance.x = xd;
            obj.disturbance.z = zd;
            obj.disturbance.src = srcd;
            obj.disturbance.amp = ampd;
            obj.disturbance.nch = size(obj.disturbance.src,4);
        end

        function obj = drawroi(obj,source,type,options)
            arguments
                obj
                source {mustBeMember(source, {'actuator', 'disturbance'})}
                type {mustBeMember(type, {'packet', 'profile'})}
                options.index (1,1) double = 1
                options.levels (1,:) double = linspace(-1,1,50)
                options.clim (1,:) double = [-1,1]*0.2
                options.clabel {mustBeA(options.clabel, {'char', 'string'})} = '(u-u_{ref})/u_e'
            end
            x = obj.(source).x;
            z = obj.(source).z;
            v = squeeze(obj.(source).src(:,:,options.index,:));
            rposition = obj.(source).rpos.(type);
            switch type
                case 'packet'
                    draw = 'drawpolygon';
                    rnumber = obj.(source).nch;
                case 'profile'
                    draw = 'drawrectangle';
                    rnumber = 1;
            end
            obj.guip = cellplot('contourf',x,z,v,...
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
            obj.guip.source = source;
            obj.guip.type = type;
        end

        function obj = nextroi(obj)
            source = obj.guip.source;
            ax = obj.guip.axs; 
            arrayfun(@(a)set(a,'Visible','off'),ax.Children)
            c = flip(findobj(ax,'type','contour'));
            r = flip(findobj(ax,'type','images.roi.Polygon'));
            if obj.cnt == obj.(source).nch
                obj.cnt = 1;
            end
            c(obj.cnt).Visible='on';
            r(obj.cnt).Visible='on';
            if obj.cnt <= obj.(source).nch
                obj.cnt = obj.cnt + 1;
            end
        end

        function obj = setroi(obj,optpack)
            arguments
                obj 
                optpack.window {mustBeMember(optpack.window, {'none', 'tukeywin'})} = 'tukeywin' % enable weight by tukeywin 
                optpack.winfactor (1,1) double = 0.75 % tukeywin scale factor
                optpack.filt {mustBeMember(optpack.filt, {'none', 'gaussian'})} = 'gaussian'
                optpack.filtker (1,:) double = [4, 4]
                optpack.filtkerparam (1,1) double = 0.2
                optpack.isflip (1,1) logical = true
            end
            source = obj.guip.source;
            type = obj.guip.type;
            r = obj.guip.resfunc();
            obj.(source).rpos.(type) = r.rgpos;
            switch type
                case 'packet'
                    func = @sliceWeightPackets;
                    arg = namedargs2cell(optpack);
                case 'profile'
                    func = @sliceFitProfiles;
                    arg = {};
            end
            obj.(source) = func(obj.(source),arg{:});
        end

        function obj = control(obj,x0,lb,ub,n,ampd,param,options)
            arguments
                obj
                x0 (1,:) double % initial approximation
                lb (1,:) double % lower boundary
                ub (1,:) double % upper boundary
                n (1,1) double % norm order
                ampd (1,1) double % disturbance packet amplitude
                param.solver {mustBeMember(param.solver, {'linear-regression', 'fmincon', 'ga'})} = 'fmincon'
                options.FiniteDifferenceType {mustBeMember(options.FiniteDifferenceType, {'forward', 'central'})} = 'forward'
                options.ConstraintTolerance (1,1) double = 1e-3
                options.MaxIterations (1,1) {mustBeInteger} = 10000
                options.DiffMinChange (1,1) double = 0.005
                options.DiffMaxChange (1,1) double = 0.5
                options.StepTolerance (1,1) double = 1e-6
                options.MaxFunctionEvaluations (1,1) {mustBeInteger} = 2000
            end

            obj.result = struct(norm = n, ...
                pack = struct(), ...
                prof = struct(x = obj.actuator.prof.x(1), z = obj.actuator.prof.z));

            y = obj.disturbance.prof.fsum(ampd);
            Y = obj.disturbance.pack.fsum(ampd);
            obj.result.prof.coff = y;
            obj.result.pack.coff = Y;

            switch param.solver
                case 'linear-regression'
                    obj.result.solver = 'linear-regression';
                    % P*I*(1/x0)*u+y=0;
                    P = cellfun(@(f,x)f(x),obj.actuator.prof.fi,num2cell(x0)','UniformOutput',false);
                    P = cat(2,P{:});
                    T = P*diag(1./x0);
                    u = mldivide(T,-y);
                    obj.result.prof.u = u;
                    obj.result.prof.con = T*u+y;
                    P = cellfun(@(f,x,u)f(x)*u/x,obj.actuator.pack.fi,num2cell(x0)',...
                        num2cell(u),'UniformOutput',false);
                    P = sum(cat(3,P{:}),3);
                    obj.result.pack.con = P+Y;
                otherwise
                    % define solver handle
                    slvf = str2func(param.solver);
                    % define problem
                    problem = struct(solver = param.solver, A = [], b = [], Aeq = [], beq = []);
                    problem.solver = param.solver;
                    problem.x0 = x0;
                    problem.lb = lb;
                    problem.ub = ub;
                    objective = @(x)norm(obj.actuator.prof.fsum(x)+y,n);
                    % configure problem according to solver
                    switch param.solver
                        case 'fmincon'
                            obj.result.solver = 'interior-point';
                            problem.objective = objective;
                            arg = namedargs2cell(options);
                            problem.options = optimoptions('fmincon','Algorithm','interior-point','PlotFcn',...
                                {@optimplotx, @optimplotfval, @optimplotfirstorderopt});
                        case 'ga'
                            obj.result.solver = 'genetic-algorithm';
                            problem.nvars = obj.actuator.nch;
                            problem.fitnessfcn = objective;
                            problem.options = optimoptions('ga','ConstraintTolerance',1e-6,...
                                'PlotFcn',{@gaplotbestf, @gaplotscores, @gaplotdistance});
                    end
                    obj.result.prof.problem = problem;
                    % solve
                    u = slvf(problem);

                    obj.result.prof.u = u;
                    obj.result.prof.con = obj.actuator.prof.fsum(u)+y;
                    obj.result.pack.con = obj.actuator.pack.fsum(u)+Y;
            end
            % estimate scores
            obj.result.prof.ncoff = norm(obj.result.prof.coff,n);
            obj.result.prof.ncon = norm(obj.result.prof.con,n);
        end

        function showresult(obj,options)
            arguments
                obj
                options.levels (1,:) double = linspace(-1,1,50)
                options.clim (1,:) double = [-1,1]*0.2
                options.label = '(u-u_{ref})/u_e'
                options.iszflip (1,1) logical = true % legacy `loadpiv` import
            end
            xposlab = sprintf("x=%.1fmm",obj.result.prof.x);
            n = obj.result.norm;
            ncoff = obj.result.prof.ncoff;
            ncon = obj.result.prof.ncon;
            nlabel = sprintf("n^{off}_{%d}=%.4f; n^{on}_{%d}=%.4f; n^{on}_{%d}/n^{off}_{%d}=%.4f",...
                n,ncoff,n,ncon,n,n,ncon./ncoff);

            z = obj.result.prof.z;
            coff = obj.result.prof.coff;
            con = obj.result.prof.con;
            u = obj.result.prof.u;

            [xl1,xl2] = bounds(cell2mat(obj.actuator.prof.vis.lim),'all'); xl = [xl1,xl2];

            switch obj.result.solver
                case 'linear-regression'
                    llab = "x";
                otherwise
                    x0 = obj.result.prof.problem.x0;
                    lb = obj.result.prof.problem.lb;
                    ub = obj.result.prof.problem.ub;
                    u = cat(1,u,lb,ub,x0)';
                    llab = ["x","lb","ub","x0"];
            end

            c = cellplot({'plot','bar'},{z,[]},{cat(2,coff,con),u},pbaspect=[3,1,1],...
                xlim={xl,'auto'},legend='on',lstring={{["off","on"]},{llab}},...
                xlabel={'z, mm','channel'},ylabel={options.label,'action'},...
                title={obj.result.solver,''},subtitle={xposlab,nlabel},docked=true);
        
            c = findobj(c,'type','Bar');
            la = ones(1,numel(c)); la(2:end) = 0.25;
            arrayfun(@(x,a)set(x,'FaceAlpha',a,'EdgeAlpha',a),c,la(:));

            x = obj.actuator.x;
            z = obj.actuator.z;
            coff = obj.result.pack.coff;
            con = obj.result.pack.con;
            if options.iszflip
                z = flip(z,1);
            end
            c = cellplot('contourf',x,z,cat(3,coff,con),axis='equal',xlabel='x, mm',...
                ylabel='z, mm',subtitle={'',nlabel},colorbar='on',...
                clabel=options.label,docked=true,axpos=nan,clim=options.clim,...
                levels=options.levels,split=true,legend='on',lstring={{"off"},{"on"}},...
                llocation='best',title={'',obj.result.solver});
            ax = c(1).Parent;
            xline(ax,obj.result.prof.x,'Color','black','DisplayName','control')
        end

        function s = exportroi(obj,source,type)
            arguments (Input)
                obj 
                source {mustBeMember(source, {'actuator', 'disturbance'})}
                type {mustBeMember(type, {'packet', 'profile'})}
            end
            arguments (Output)
                s string
            end
            s = strcat(source,".rpos.",type,"={{",join(cellfun(@(x)string(mat2str(x)),obj.(source).rpos.(type){1}),newline),"}}");
        end
    end
end

function dev = sliceWeightPackets(dev,options)
    arguments (Input)
        dev struct
        options.window {mustBeMember(options.window, {'none', 'tukeywin'})} = 'tukeywin' % enable weight by tukeywin 
        options.winfactor (1,1) double = 0.75 % tukeywin scale factor
        options.filt {mustBeMember(options.filt, {'none', 'gaussian'})} = 'gaussian'
        options.filtker (1,:) double = [4, 4]
        options.filtkerparam (1,1) double = 0.2
        options.isflip (1,1) logical % enable fit in range [-flip(amp),amp] (concatenate inverse packets)
    end
    arguments (Output)
        dev struct
    end
    x = dev.x;
    z = dev.z;
    src = dev.src;
    amp = dev.amp;
    rpos = dev.rpos.packet;
    % filt data
    switch options.filt
        case 'gaussian'
            src = imfilter(src,fspecial(options.filt,options.filtker,options.filtkerparam),'symmetric');
    end
    if options.isflip
        amp = [-flip(amp),amp];
        src = cat(3,-flip(src,3),src);
    end
    arg = num2cell(size(src));
    if ndims(src) == 4; arg{end} = ones(1,arg{end}); end
    src = squeeze(mat2cell(src,arg{:}));
    % slice data
    src = cellfun(@(p,d)maskcutdata(p,x,z,d,dims=[1,2],fill='outnan',shape='trim'),...
        rpos{1},src,'UniformOutput',false);
    src = cat(ndims(src{1})+1,src{:});
    % weight data
    win = [];
    switch options.window
        case 'tukeywin'
            ni = ~isnan(src);
            sz = size(src);
            for i = 1:prod(sz(2:end))
                win(:,i) = zeros(1,numel(src(:,i)));
                ind = find(ni(:,i));
                win(ind,i) = tukeywin(numel(ind),options.winfactor);
            end
            src(~ni) = 0;
            win = reshape(win,sz);
            src = src.*win;
        otherwise
            src(isnan(src)) = 0;
    end
    % linear piecewise fit of packets dependence on amplitude
    x = double(x);
    z = double(z);
    [Z,X,A] = ndgrid(unique(z),unique(x),amp);
    ft = cellfun(@(v)fitn(Z,X,A,v),...
        squeeze(mat2cell(src,arg{:})),'UniformOutput',false);
    fi = cellfun(@(f) @(a) f(z,x,a*ones(size(z))), ft, 'UniformOutput', false);
    fsum = @(a) evalresp(fi,a);
    dev.pack = struct(win=win,src=src,amp=amp);
    dev.pack.fi = fi;
    dev.pack.fsum = fsum;
end

function dev = sliceFitProfiles(dev)
    arguments (Input)
        dev struct
    end
    arguments (Output)
        dev struct
    end
    x = dev.x;
    z = dev.z;
    amp = dev.pack.amp;
    src = dev.pack.src;
    win = dev.pack.win;
    rpos = dev.rpos.profile;

    % slice windown
    win = maskcutdata(rpos{1}{1},x,z,win,dims=[1,2],...
        fill='none',shape='bounds',isrectangle=true);
    % slice data
    [src,x,z] = maskcutdata(rpos{1}{1},x,z,src,dims=[1,2],...
        fill='none',shape='bounds',isrectangle=true);
    % averaging along x-axis dimension
    x = mean(x,2); z = mean(z,2); win = squeeze(mean(win,2)); src = squeeze(mean(src,2));
    % linear piecewise fit of profiles dependence on amplitude
    arg = num2cell(size(src));
    if ndims(src) == 3; arg{end} = ones(1,arg{end}); end
    [A, Z] = meshgrid(amp, z);
    ft = cellfun(@(v) fit([Z(:), A(:)], v(:), 'linearinterp'), ...
        squeeze(mat2cell(src,arg{:})), 'UniformOutput', false);
    fi = cellfun(@(f) @(a) f(z, a*ones(numel(z),1)), ft, 'UniformOutput', false);
    fsum = @(a) evalresp(fi,a);

    % interpolate on refine mesh
    vis = struct;
    [vis.a, vis.z] = meshgrid(linspace(amp(1),amp(end)), z);
    vis.src = cellfun(@(f)f(vis.z,vis.a),ft,'UniformOutput',false);
    % create z-axis limits
    win = win(:,1,:);
    arg = num2cell(size(win));
    arg{end} = ones(1,arg{end});
    vis.lim = cellfun(@(w)[min(z(w~=0)),max(z(w~=0))],...
        squeeze(mat2cell(win,arg{:})), 'UniformOutput', false);

    dev.prof = struct(x=x,z=z,src=src,amp=amp,vis=vis);
    dev.prof.fi = fi;
    dev.prof.fsum = fsum;
end

function u = evalresp(f,a)
    arguments (Input)
        f (1,:) cell
        a (1,:) double
    end
    arguments (Output)
        u (:,:,:) double
    end
    u = cellfun(@(f,a)f(a),f,num2cell(a),'UniformOutput',false);
    u = squeeze(sum(cat(ndims(u{1})+1,u{:}),ndims(u{1})+1,'omitmissing'));
end