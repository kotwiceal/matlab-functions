function varargout = procspecn(data, kwargs)
    %% Process a multidimensional short-time Fourier transform.

    arguments (Input)
        data double
        kwargs.ftdim (1,:) double = [] % dimensions to apply transform
        kwargs.chdim (1,:) double = [] % dimensions to process cross spectra
        kwargs.winlen (1,:) double = 1024 % transform window lengths
        kwargs.overlap (1,:) double = 512 % transform window strides
        kwargs.offset (1,:) {mustBeA(kwargs.offset, {'double', 'cell '})} = 0 % sliding window offset at performing STFT
        kwargs.side {mustBeMember(kwargs.side, {'single', 'double'})} = 'single' % spectra process mode
        kwargs.type {mustBeMember(kwargs.type, {'amp', 'power', 'psd'})} = 'power' % spectra process mode
        kwargs.avg (1,:) logical = false % averaging by statistics of spectra
        kwargs.fs (1,:) double = [] % sampling frequency
        kwargs.center (1,:) logical = true % centre data at transform
        kwargs.winfun {mustBeMember(kwargs.winfun, {'uniform', 'hann', 'hanning', 'hamming'})} = 'hanning' % to weight data at transform
        kwargs.norm (1,1) logical = true % norm for spectral density
        kwargs.ans {mustBeMember(kwargs.ans, {'double', 'cell', 'struct'})} = 'double' % output data format
    end

    arguments(Output,Repeating)
        varargout 
    end

    szd = size(data);
    dimsd = ndims(data);
    kwargs.overlap(isnan(kwargs.overlap)) = 1;
    dimsf = numel(kwargs.winlen);

    % parse arguments
    if isempty(kwargs.ftdim); kwargs.ftdim = 1:dimsf; end
    if isempty(kwargs.fs); kwargs.fs = ones(1, dimsf); end
    if isscalar(kwargs.fs); kwargs.fs = repmat(kwargs.fs, dimsf); end
    if isa(kwargs.winfun, 'char') | isa(kwargs.winfun, 'string'); kwargs.winfun = repmat({kwargs.winfun}, 1, dimsf); end
    if isa(kwargs.side, 'char') | isa(kwargs.side, 'string'); kwargs.side = repmat({kwargs.side}, 1, dimsf); end
    if isscalar(kwargs.avg); kwargs.avg = repmat(kwargs.avg, 1, dimsf); end
    if isscalar(kwargs.center); kwargs.center = repelem(kwargs.center, dimsf); end

    % size validation
    if numel(kwargs.ftdim) ~= dimsf; error('`ftdim` size must be equal `winlen`'); end
    if numel(kwargs.fs) ~= dimsf; error('`fs` size must be equal `winlen`'); end
    if numel(kwargs.winfun) ~= dimsf; error('`winfun` size must be equal `winlen`'); end
    if numel(kwargs.side) ~= dimsf; error('`side` size must be equal `winlen`'); end
    if numel(kwargs.avg) ~= dimsf; error('`avg` size must be equal `winlen`'); end
    if numel(kwargs.center) ~= dimsf; error('`center` size must be equal `winlen`'); end

    if ~(isscalar(kwargs.chdim) | isempty(kwargs.chdim)); error('`chdim` must be empty or scalar'); end

    kwargs.winlen(isnan(kwargs.winlen)) = szd(kwargs.ftdim(isnan(kwargs.winlen)));

    kwargs.type = string(kwargs.type);

    indcentr = kwargs.ftdim(kwargs.center);

    % generate frequency grid
    f = cell(1, dimsf);
    for i = 1:dimsf
        switch kwargs.side{i}
            case 'single'
                f{i} = freqspace(kwargs.winlen(i));
            case 'double'
                [f{i}, ~] = freqspace(kwargs.winlen(i));
        end
        f{i} = f{i}*kwargs.fs(i)/2;
    end
    df = prod(cellfun(@(f) abs(f(2)-f(1)), f, 'UniformOutput', true));

    % create multidimensional window function
    winfun = repelem({'uniform'}, numel(1:max(kwargs.ftdim)));
    winfun(kwargs.ftdim) = kwargs.winfun; kwargs.winfun = winfun;
    kwargs.winfun = cellfun(@(x) str2func(x), kwargs.winfun, 'UniformOutput', false);
    mask = ones(1, numel(1:max(kwargs.ftdim))); mask(kwargs.ftdim) = kwargs.winlen; kwargs.winlen = mask;
    win = kwargs.winfun{1}(kwargs.winlen(1));
    for i = 2:numel(kwargs.winlen); win = win.*shiftdim(kwargs.winfun{i}(kwargs.winlen(i)),-i+1); end

    % calculate correction factor
    switch kwargs.type
        case 'amp'
            funccor = @mean;
        otherwise
            funccor = @rms;
    end
    cf = prod(cellfun(@(i) kwargs.winlen(i)./funccor(kwargs.winfun{i}(kwargs.winlen(i))), num2cell(1:numel(kwargs.winlen)), 'UniformOutput', true)).^2;

    % process spectra
    kernel = nan(1, dimsd); kernel(kwargs.ftdim) = kwargs.winlen(kwargs.ftdim);
    stride = ones(1, dimsd); stride(kwargs.ftdim) = kwargs.overlap;
    offset = zeros(1, dimsd); offset(kwargs.ftdim) = kwargs.offset;
    spec = nonlinfilt(@specker, data, kernel = kernel, stride = stride, offset = offset, padval = false);
    dimss = ndims(spec);
    dimsb = setdiff(1:dimss, 1:dimsd);
    if isempty(dimsb); dimsb = ndims(spec); end
    if isscalar(dimsb); kwargs.avg = logical(prod(kwargs.avg)); end

    if kwargs.norm;  spec = spec./prod(kwargs.winlen).^2; end % norm spectra

    kwargs.ftdims = kwargs.ftdim(cellfun(@(s) strcmp(s, 'single'), kwargs.side, 'UniformOutput', true));
    for i = setdiff(kwargs.ftdim, kwargs.ftdims)
        spec = fftshift(spec, i); % shift nodes for double frequency range
    end

    if ~isempty(kwargs.ftdims)
        szs = size(spec);
        szs(kwargs.ftdims) = cellfun(@(x) numel(x), f, 'UniformOutput', true);
        ind = cellfun(@(x) 1:x, num2cell(szs), 'UniformOutput', false);
        spec = spec(ind{:})*sqrt(2); % truncate spectra & correct amplitude

        % zero frequency without amplitude correction
        ind(kwargs.ftdims) = num2cell(ones(1, numel(kwargs.ftdims)));
        spec(ind{:}) = spec(ind{:})/sqrt(2); 
    end

    if ismember(kwargs.type, ["power", "psd"])
        if isempty(kwargs.chdim)
            spec = spec.*conj(spec);
        else
            dimsb = dimsb - 1;
            szs = size(spec);
            szst = szs; szst(kwargs.chdim) = [];
            indg = cellfun(@(x) 1:x, num2cell(szst), 'UniformOutput', false);
            indi = cellfun(@(x) 1:x, num2cell(szs), 'UniformOutput', false);
            indj = indi;

            temp = zeros([szst, szs(kwargs.chdim), szs(kwargs.chdim)]);
            for i = 1:szs(kwargs.chdim)
                indi{kwargs.chdim} = i;
                for j = 1:szs(kwargs.chdim)
                    indj{kwargs.chdim} = j;
                    indt = cat(2, indg, i, j);
                    if j < i
                        temp2 = nan; 
                    else
                        temp2 = spec(indi{:}).*conj(spec(indj{:}));
                    end
                    temp(indt{:}) = temp2;
                end
            end
            spec = temp; clear temp temp2;
        end
    end

    % average spectra
    if sum(kwargs.avg) >= 1; spec = squeeze(mean(spec, dimsb(kwargs.avg))); end

    spec = spec.*cf; % window function correction factor

    if kwargs.type == "psd"; spec = spec./df; end % norm to spectral density

    % build frequency grid
    [f{:}] = ndgrid(f{:});
    if isscalar(f); f = f{1}; end

    switch kwargs.ans
        case 'double'
            varargout{1} = spec;
            varargout{2} = f;
        case 'cell'
            szs = size(spec);
            indg = cellfun(@(x) 1:x, num2cell(szs(1:end-2)), 'UniformOutput', false);

            temp = cell(szd(kwargs.chdim));
            for i = 1:szd(kwargs.chdim)
                for j = 1:szd(kwargs.chdim)
                    indt = cat(2, indg, i, j);
                    temp{i,j} = spec(indt{:});
                end
            end
            spec = temp; clear temp;
            varargout{1} = spec;
            varargout{2} = f;
        case 'struct'
            varargout{1} = struct(spec = spec, f = f);
    end

    function x = specker(x, ~)
        x = squeeze(x);
        for k = indcentr; x = normalize(x, k, 'center'); end % center data
        x = x.*win; % weight data by window function
        for k = kwargs.ftdim; x = fft(x, [], k); end % process mult. dim. FFT
    end

end

function w = uniform(n)
    w = ones(n, 1);
end