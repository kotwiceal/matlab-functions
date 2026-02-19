function varargout = statdecom(bins,data,param,filt,cons,prob,popt,pfilt)

    arguments (Input)
        bins
        data
        param.dist {mustBeMember(param.dist, {'chi', 'beta', 'gamma', 'gumbel', 'gauss'})} = 'beta' % approximation distribution family
        param.objnorm (1,1) double = 2 % objective function norm
        param.pass (1,1) {mustBeInteger} = 1 % to recursive approximation
        param.ans {mustBeMember(param.ans, {'cell', 'struct'})} = 'cell' % output data format
        param.cast {mustBeMember(param.cast, {'single', 'double'})} = 'double' % cast data
        %% filter: statistical distribution estimation
        filt.kernel (1,:) double = []
        filt.stride (1,:) double = []
        filt.ndim (1,:) double = []
        filt.padval (1,:) = false
        %% constraints
        cons.mean (1,:) {mustBeA(cons.mean, {'double', 'cell'})} = []
        cons.mode (1,:) {mustBeA(cons.mode, {'double', 'cell'})} = [] 
        cons.var (1,:) {mustBeA(cons.var, {'double', 'cell'})} = []
        cons.amp (1,:) {mustBeA(cons.amp, {'double', 'cell'})} = []
        %% undefined variables
        prob.x0 double = [] % inital approximation
        prob.Aeq (:,:) double = [] % linear optimization equality constraint matrix
        prob.beq (1,:) double = [] % linear optimization equality constraint right side
        prob.Aineq (:,:) double = [] % linear optimization inequality constraint matrix
        prob.bineq (1,:) double = [] % linear optimization inequality constraint right side
        prob.lb (1,:) double = [] % lower bound of undefined variables
        prob.ub (1,:) double = [] % upper bound of undefined variables
        prob.nonlcon = [] % non-linear optimization constraint function
        %% optimization
        popt.algorithm {mustBeMember(popt.algorithm, {'interior-point','sqp',...
            'trust-region-reflective','active-set'})} = 'interior-point'
        popt.maxfunctionevaluations (1,1) double = 1e3
        popt.maxiterations (1,1) double = 3e3
        popt.diffmaxchange (1,1) double = 1e-4
        popt.display {mustBeMember(popt.display, {'on', 'off'})} = 'off'
        popt.honorbounds (1,1) logical = true
        %% pre-filtering
        pfilt.prefilt {mustBeMember(pfilt.prefilt, {'none', 'gaussian', 'average', 'sobel', 'median'})} = 'none'
        pfilt.prefiltker (1,:) {mustBeA(pfilt.prefiltker, {'double', 'cell'})} = [] % kernel size
        pfilt.prefiltdim (1,:) {mustBeA(pfilt.prefiltdim, {'double', 'cell'})} = [] % filter dimension 
        pfilt.prepadval {mustBeA(pfilt.prepadval, {'double', 'char', 'string', 'logical', 'cell'})} = 'symmetric' % padding value
    end

    arguments (Output, Repeating)
        varargout
    end

    % compute statistical distributions
    filt = namedargs2cell(filt);
    hist = nonlinfilt(@(x, ~) histcounts(x(:), bins, 'Normalization', 'pdf'), data, filt{:});
    bins = bins(2:end)-diff(bins)/2;

    % assembly approximation distribution
    sarg = struct(chi = 2, beta = 3, gamma = 3, gumbel = 3, gauss = 3);
    if ~isa(param.dist, 'cell'); param.dist = {param.dist}; end
    narg = cellfun(@(d) sarg.(d), param.dist);
    index = mat2cell(1:sum(narg), 1, narg);

    % redefine list CDFs
    lcdf = struct(chi = @chi2cdf, beta = @betacdf, gamma = @gamcdf, gumbel = @evcdf, gauss = @normcdf);
    lcdf = structfun(@(f) @(a, x) f(x, a{2:end}), lcdf, UniformOutput = false);

    % redefine list PDFs
    lpdf = struct(chi = @chi2pdf, beta = @betapdf, gamma = @gampdf, gumbel = @evpdf, gauss = @normpdf);
    lpdf = structfun(@(f) @(a, x) a{1}*f(x, a{2:end}), lpdf, UniformOutput = false);

    % statistical mode functions
    fstatmode = @(p) cellfun(@(d,i) lpdf.(d)(num2cell(p(i)), bins), param.dist, index, 'UniformOutput', false);

    % approximation function
    fapprox = @(a) sum(cell2mat(fstatmode(a)), 2);

    % objective function
    fobj = @(a, x) norm(omitundef(fapprox(a)-x), param.objnorm);

    % define handler to compute statistical moments
    fdparam = @(p) cell2mat(cellfun(@(d,i) distparam(p(i), d), param.dist(:), index(:), 'UniformOutput', false));

    % inequality constraints
    cons = structfun(@(s) terop(isempty(s), nan(1,2), s), cons, 'UniformOutput', false);
    cons = parseargs(numel(param.dist), cons, ans = 'struct');
    cons = structfun(@(s) cellfun(@(c) terop(isempty(c), nan(1,2), c), s, ...
        'UniformOutput', false), cons, 'UniformOutput', false);
    cons = namedargs2cell(cons);
    cons = permute(cell2arr(cellfun(@(varargin) cat(1, varargin{:}), cons{2:2:end}, ...
        'UniformOutput', false)), [3, 1, 2]); % dimensions [modes=vars, moments=4, limits=2]
    cons(:,:,1) = (-1)*cons(:,:,1);

    % initialize optimization problem
    prob.nonlcon = @nonlcon; % non-linear constraint function
    args = namedargs2cell(popt);
    prob.options = optimoptions('fmincon', args{:});
    args = namedargs2cell(prob);

    % compute approximation distribution coefficients
    if isvector(hist); hist = hist(:); end
    if isvector(prob.x0)
        sz = size(hist);
        arg = num2cell([1, sz(2:end)]);
        coef = repmat(prob.x0(:), arg{:});
    else
        coef = prob.x0;
    end
    for i = 1:param.pass
        coef = cellfilt(pfilt.prefilt, coef, kernel = pfilt.prefiltker,...
            ndim = pfilt.prefiltdim, padval = pfilt.prepadval);
        coef = nonlinfilt(@(x, y, ~) fmincon(@(a) fobj(a, x), y, args{4:2:end}), hist, coef, ...
            kernel = nan, padval = false);
    end

    % compute statistical mode parameters
    mparam = nonlinfilt(@(p,~) fdparam(p), coef, kernel = nan, padval = false);

    % compute statistical mode PDFs
    mpdf = cellfun(@(d,i) nonlinfilt(@(p,~) lpdf.(d)(num2cell(p(i)), bins), ...
        coef, kernel = nan, padval = false), param.dist, index, 'UniformOutput', false);

    % compute statistical mode CDFs
    mcdf = cellfun(@(d,i) nonlinfilt(@(p,~) lcdf.(d)(num2cell(p(i)), bins), ...
        coef, kernel = nan, padval = false), param.dist, index, 'UniformOutput', false);

    switch param.ans
        case 'cell'
            varargout = cell(1,6);
            [varargout{:}] = deal(coef,mpdf,mcdf,bins,his,mparam);
        case 'struct'
            varargout{1} = struct(coef=coef,mpdf={mpdf},mcdf={mcdf},bins=bins,rpdf=hist,mparam=mparam);
    end

    function [c, ceq] = nonlcon(x)
        ceq = [];
        c = omitundef(fdparam(x).*shiftdim([-1,1],-1)-cons);
    end

    function y = omitundef(x)
        y = x(~isnan(x)&~isinf(x));
    end

    function p = distparam(x, dist)   
        switch dist
            case 'gauss'
                dmean = x(2);
                dmode = x(2);
                dvar = x(3);
                damp = x(1)*normpdf(dmode, x(2), x(3));
            case 'chi'
                dmean = x(2);
                dmode = max([0, x(2)-2]);
                dvar = 2*x(2);
                damp = x(1)*chi2pdf(dmode, x(2));
            case 'beta'
                dmean = x(2)/(x(2)+x(3));
                dmode = (x(2)-1)/(x(2)+x(3)-2);
                dvar = x(2)*x(3)/(x(2)+x(3))^2/(x(2)+x(3)+1);
                damp = x(1)*betapdf(dmode, x(2), x(3));
            case 'gamma'
                dmean = x(2)*x(3);
                if (x(2) >= 1)
                    dmode = (x(2)-1)*x(3);
                    damp = x(1)*gampdf(dmode, x(2), x(3));
                else
                    dmode = 0;
                    damp = nan;
                end
                dvar = x(2)*x(3)^2;
            case 'gumbel'
                ec = 0.57721;
                dmean = x(2)+x(3)*ec;
                dmode = x(2);
                dvar = pi^2/6*x(3)^2;
                damp = x(1)*evpdf(dmode, x(2), x(3));
        end
        p = [dmean, dmode, dvar, damp];
    end

    % redefine gumbel distribution

    function y = evpdf(x, m, b)
        y = 1/b*exp(-(x-m)/b-exp(-(x-m)/b));
    end

    function y = evcdf(x, m, b)
        y = exp(-exp(-(x-m)/b));
    end

end