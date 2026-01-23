function varargout = fspatialn(n, varargin, param)
    arguments (Input)
        n (1,1) {mustBeInteger}
    end
    arguments (Input, Repeating)
        varargin
    end
    arguments (Input)
        param.ans {mustBeMember(param.ans, {'cell', 'ncell'})} = 'cell'
    end
    arguments (Output, Repeating)
        varargout
    end

    nv = numel(varargin);

    if nv <= n
        varargin = cat(2, varargin, repelem(varargin(end), n - nv));
    end

    m = cell(1, n);
    [m{:}] = ndgrid(varargin{:});

    f = prod(cat(n+1, m{:}), n+1);
    if n == 1; n = n + 1; end
    r = 1:n;
    f = arrayfun(@(x) permute(f, circshift(r, x)), r-1, 'UniformOutput', false);

    switch param.ans
        case 'cell'
            varargout = f;
        case 'ncell'
            varargout{1} = f;
    end

end