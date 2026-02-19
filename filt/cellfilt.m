function varargout = cellfilt(name,varargin,param)
    arguments (Input)
        name  {mustBeMember(name , {'none', 'gaussian', 'average', 'sobel', 'median', 'fillmiss', 'griddatan', 'fillmissn', 'interpn'})}
    end
    arguments (Input, Repeating)
        varargin
    end
    arguments (Input)
        param.kernel {mustBeA(param.kernel, {'double', 'cell'})} = [] % kernel size
        param.ndim {mustBeA(param.ndim, {'double', 'cell'})} = [] % filter dimension 
        param.padval {mustBeA(param.padval, {'double', 'char', 'string', 'logical', 'cell'})} = 'symmetric' % padding value
        param.method {mustBeMember(param.method, {'none', 'linear', 'nearest', 'natural', 'cubic', 'v4'})} = 'nearest'
        param.arg (1,:) double = []
    end
    arguments (Output, Repeating)
        varargout
    end

    if ~isa(name, 'cell'); name = {name}; end

    param.name = name;
    args = parseargs(numel(name), param, ans = 'joint');
    args = cellfun(@(x) cellfun(@(y) teropf(isa(y,'cell'), @() y{1}, @() y), x, 'UniformOutput', false), ...
        args, 'UniformOutput', false);

    for i = 1:numel(args)
        varargin = cellfun(@(x) filter(x,args{i}{:}), varargin, 'UniformOutput', false);
    end

    clearAllMemoizedCaches;

    varargout = varargin;

end

function data = filter(data, param, filt)
    %% Advance multi-dimensional data filtering.

    arguments (Input)
        data
        % filter name
        param.name {mustBeMember(param.name, {'none', 'gaussian', 'average', 'sobel', 'median', 'fillmiss', 'griddatan', 'fillmissn', 'interpn'})} = 'gaussian'
        param.method {mustBeMember(param.method, {'none', 'linear', 'nearest', 'natural', 'cubic', 'v4'})} = 'nearest' % at specifying `filtker=fillmiss`
        param.zero2nan (1,1) logical = true
        param.arg (1,:) double = []
        filt.kernel (1,:) double = [] % kernel size
        filt.ndim (1,:) double = [] % number dimensions
        filt.padval {mustBeA(filt.padval, {'double', 'char', 'string', 'logical', 'cell'})} = 'symmetric' % padding value
    end

    arguments (Output)
        data
    end

    if (isempty(filt.kernel) & isempty(filt.ndim)) | strcmp(param.name,"none") | isscalar(data); return; end

    if isempty(filt.ndim); filt.ndim = 1:numel(filt.kernel); end

    switch param.name
        case 'median'
            func = @(x, ~) squeeze(median(x, filt.ndim, 'omitmissing'));
            filt.slice = true;
        case 'fillmiss'
            if param.method ~= "none"
                filt.padval = false;
                filt.kernel = size(data, filt.ndim);
                if param.zero2nan; data(data==0) = nan; end
                switch numel(filt.ndim)
                    case 1
                        func = @(x, ~) fillmissing(squeeze(x), param.method);
                    case 2
                        func = @(x, ~) fillmissing2(squeeze(x), param.method);
                end
            end
        case 'fillmissn'
            filt.padval = false;
            filt.kernel = size(data, filt.ndim);
            if isscalar(filt.kernel); filt.kernel = [filt.kernel, 1]; end
            p = cellfun(@(x)linspace(0,1,x),num2cell(size(data,filt.ndim)),'UniformOutput',false);
            [p{:}] = ndgrid(p{:});
            p = cellfun(@(x)x(:),p,'UniformOutput',false);
            p = cat(2,p{:});
            func = @(x,~) reshape(griddatan(p(~isnan(x(:)),:),x(~isnan(x(:))),p,param.method),filt.kernel);
        case 'griddatan'
            filt.padval = false;
            p = cellfun(@(x)linspace(0,1,x),num2cell(size(data,filt.ndim)),'UniformOutput',false);
            [p{:}] = ndgrid(p{:});
            p = cellfun(@(x)x(:),p,'UniformOutput',false);
            q = cellfun(@(x)linspace(0,1,x),num2cell(filt.kernel),'UniformOutput',false);
            [q{:}] = ndgrid(q{:});
            q = cellfun(@(x)x(:),q,'UniformOutput',false);
            func = @(x,~) reshape(griddatan(cat(2,p{:}),x(:),cat(2,q{:}),param.method),filt.kernel);
        case 'interpn'
            filt.padval = false;
            p = cellfun(@(x)linspace(0,1,x),num2cell(size(data,filt.ndim)),'UniformOutput',false);
            [p{:}] = ndgrid(p{:});
            q = cellfun(@(x)linspace(0,1,x),num2cell(filt.kernel),'UniformOutput',false);
            [q{:}] = ndgrid(q{:});
            if isscalar(filt.kernel); filt.kernel = [filt.kernel, 1]; end
            kernel = filt.kernel;
            func = @(x,~) reshape(interpn(p{:},x,q{:},param.method),kernel);
            filt.kernel = nan(1,numel(filt.kernel));
        otherwise
            switch param.name
                case 'average'
                    ker = squeeze(ones([filt.kernel,1])./prod(filt.kernel));
                case 'sobel'
                    ker = fspatialn(numel(filt.ndim),[1,0,-1],[1,2,1]);
                    if isvector(ker); k = numel(ker); else; k = size(ker); end
                    filt.kernel = k;
                case 'gaussian'
                    ker = gausian(filt.kernel,param.arg);
            end
            if isvector(ker); ndker = 1; else; ndker = 1:ndims(ker); end
            func = @(x,~) squeeze(tensorprod(ker, x, ndker, filt.ndim));
            filt.slice = true;
    end

    filt = namedargs2cell(filt);

    data = nonlinfilt(func, data, filt{:});

end

function h = gausian(sz,std)
    if isempty(std); std = ones(1,numel(sz)); end
    sz = (sz-1)/2;
    std = num2cell(std);
    arg = arrayfun(@(x)-x:x,sz,'UniformOutput',false);
    [arg{:}] = ndgrid(arg{:});
    arg = cellfun(@(x,y)-x.^2./(2.*y.^2),arg,std,'UniformOutput',false);
    arg = cat(ndims(arg{1})+1,arg{:});
    h = exp(sum(arg,ndims(arg)));
    h(h<eps*max(h(:))) = 0;
    sumh = sum(h(:));
    if sumh ~= 0; h  = h/sumh; end
end