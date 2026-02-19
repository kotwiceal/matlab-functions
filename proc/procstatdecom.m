function varargout = procstatdecom(bins,data,kwarg,param,filt,cons,prob,popt,pref,postf)

    arguments (Input)
        bins
        data
        kwarg.grid {mustBeMember(kwarg.grid, {'linear', 'nearest', 'natural', 'cubic', 'v4'})} = 'linear'
        param.dist {mustBeMember(param.dist, {'chi', 'beta', 'gamma', 'gumbel', 'gauss'})} = 'beta' % approximation distribution family
        param.objnorm (1,1) double = 2 % objective function norm
        param.pass (1,1) {mustBeInteger} = 1 % to recursive approximation
        param.ans {mustBeMember(param.ans, {'cell', 'struct'})} = 'cell' % output data format
        param.cast {mustBeMember(param.cast, {'single', 'double'})} = 'double' % cast data
        %% nonlinfilt
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
        pref.prefilt {mustBeMember(pref.prefilt, {'none', 'gaussian', 'average', 'sobel', 'median'})} = 'none'
        pref.prefiltker (1,:) {mustBeA(pref.prefiltker, {'double', 'cell'})} = [] % kernel size
        pref.prefiltdim (1,:) {mustBeA(pref.prefiltdim, {'double', 'cell'})} = [] % filter dimension 
        pref.prepadval {mustBeA(pref.prepadval, {'double', 'char', 'string', 'logical', 'cell'})} = 'symmetric' % padding value
        %% post-filtering
        postf.postfilt {mustBeMember(postf.postfilt, {'none', 'gaussian', 'average', 'sobel', 'median'})} = 'none'
        postf.postfiltker (1,:) {mustBeA(postf.postfiltker, {'double', 'cell'})} = [] % kernel size
        postf.postfiltdim (1,:) {mustBeA(postf.postfiltdim, {'double', 'cell'})} = [] % filter dimension 
        postf.postpadval {mustBeA(postf.postpadval, {'double', 'char', 'string', 'logical', 'cell'})} = 'symmetric' % padding value
    end

    arguments (Output, Repeating)
        varargout
    end

    param.ans = 'struct';

    % stack arguments
    args = cellfun(@(s) namedargs2cell(s), {param, filt, cons, prob, popt, pref}, ...
        'UniformOutput', false);
    args = cat(2, args{:});
    % decompose distributions
    result = statdecom(bins, data, args{:});

    % compute PDF integral ratio
    intpdf = cellfun(@(p) squeeze(sum(p,1)), result.mpdf, 'UniformOutput', false);
    nd = ndims(intpdf{1}) + 1;
    tolintpdf = sum(cat(nd, intpdf{:}), nd);
    intermittency = cellfun(@(p) p./tolintpdf, intpdf, 'UniformOutput', false);
    intermittency = intermittency{end};

    % compute CDF intersection
    [~, index] = min(abs(result.mcdf{1}-flip(result.mcdf{2})),[],1);
    threshold = result.bins(squeeze(index));

    % filter intermittency/threshold
    [intermittency, threshold] = cellfilt(postf.postfilt, ...
        intermittency, threshold,...
        kernel = postf.postfiltker, ...
        ndim = postf.postfiltdim, ...
        padval = postf.postpadval);

    % grid intermittency/threshold
    if isempty(filt.ndim); filt.ndim = 1:numel(filt.kernel); end
    filtker = size(data, filt.ndim(~isnan(filt.kernel)));
    [intermittency, threshold] = cellfilt('interpn', ...
        intermittency, threshold,...
        kernel = filtker, ...
        method = kwarg.grid);

    % shift dimension of threshold
    perind = 1:ndims(data);
    fdim = perind;
    fdim(perind(filt.ndim(isnan(filt.kernel)))) = [];
    [~, i] = setdiff(perind, fdim);
    perind(i) = numel(fdim)+(1:numel(i));
    perind(fdim) = 1:numel(fdim);

    % compute binarized
    binarized = double(data./permute(threshold,perind)>1);

    % average binarized
    mbinarized = squeeze(mean(binarized,filt.ndim(isnan(filt.kernel))));

    varargout{1} = struct(threshold=threshold,binarized=binarized,...
        intermittency=intermittency,mbinarized=mbinarized);

    varargout{1} = structfun(@(x)cast(x,param.cast),varargout{1},'UniformOutput',false);
end