function varargout = filteval(param)
    %% Evaluate sliding window passing indexes.

    arguments (Input)
        % double/cell array containing size of filtering data
        param.szarg {mustBeA(param.szarg, {'double', 'cell'})} = []

        % data dimension to apply filter
        param.ndim {mustBeA(param.ndim, {'double', 'cell'})} = []

        % sliding window size
        param.kernel {mustBeA(param.kernel, {'double', 'cell'})} = []

        % sliding window stride
        param.stride {mustBeA(param.stride, {'double', 'cell'})} = []

        % sliding window offset
        param.offset {mustBeA(param.offset, {'double', 'cell'})} = []

        % padding value
        param.padval {mustBeA(param.padval, {'double', 'char', 'string', 'logical', 'cell'})} = nan
        
        % cast indexes to specific type
        param.cast {mustBeMember(param.cast, {'int8', 'int16', 'int32', 'int64'})} = 'int32'
        
        % enable multi dimensional slicing
        % if is not empty `param.ndim` than `param.kernel` will be modified like `param.kernel = [nan, ..., kernel, ..., nan] & param.kernel(param.ndim) = kernel`
        param.slice (1,1) logical = false

        % evaluate filter passing
        param.isfiltpass (1,1) logical = false

        % enable console output
        param.verbose (1,1) logical = false
    end

    arguments (Output, Repeating)
        varargout
    end

    timer = tic;

    if isempty(param.szarg); error('`szarg` must be not empty'); end

    if isa(param.szarg, 'double'); param.szarg = {param.szarg}; end

    narg = numel(param.szarg);
    ndimsarg = cellfun(@numel, param.szarg, 'UniformOutput', false);

    param.strideisvector = false(1, narg);

    % filter dimension validation
    if isa(param.ndim, 'double')
        param.ndim = repelem({param.ndim}, narg);
    end
    if narg ~= numel(param.ndim); error('number of filter `param.ndim` must be correspond to number of filtering array'); end

    % padding value validation
    if isempty(param.padval)
        param.padval = cellfun(@(x) num2cell(zeros(1, x)), ndimsarg, 'UniformOutput', false);
        param.ispad = cellfun(@(x) num2cell(false(1, x)), ndimsarg, 'UniformOutput', false);
    else
        if isa(param.padval, 'char'); param.padval = string(param.padval); end
        if ~isa(param.padval, 'cell') && isscalar(param.padval)
            if isa(param.padval, 'logical')
                param.ispad = param.padval; 
                param.padval = 0;
            else
                param.ispad = true;
            end
            param.padval = cellfun(@(x) repelem({param.padval}, x), ndimsarg, 'UniformOutput', false);
            param.ispad = cellfun(@(x) repelem({param.ispad}, x), ndimsarg, 'UniformOutput', false);
        else
            if isscalar(ndimsarg) && numel(param.padval) == ndimsarg{1}
                param.padval = {param.padval};
            end
            if numel(param.padval) ~= narg
                param.padval = repmat({param.padval}, 1, narg);
                for i = 1:narg
                    if numel(param.padval{i}) ~= ndimsarg{i}; error('`numel(padval)` must be equal `narg`'); end    
                end
            end
            for i = 1:narg
                if numel(param.padval{i}) ~= ndimsarg{i}; error('`numel(padval{i})` must be equal ndimsarg{i}'); end
                for j = 1:ndimsarg{i}
                    if isa(param.padval{i}{j}, 'logical')
                        param.ispad{i}{j} = param.padval{i}{j};

                        % set default padding value at enable padding without specifying value
                        if param.ispad{i}{j}; param.padval{i}{j} = 0; end
                    else
                        param.ispad{i}{j} = true;
                    end
                end
            end
        end
    end

    % kernel validation
    if isempty(param.kernel); param.kernel = param.szarg; end
    if isa(param.kernel, 'double')
        param.kernel = repelem({param.kernel}, narg);
    end
    if narg ~= numel(param.kernel); error('number of filter `param.kernel` must be equal one or correspond to number of filtering array'); end
    for i = 1:narg
        if isempty(param.ndim{i})
            if isvector(param.kernel{i})
                n = numel(param.kernel{i});
            else
                n = ndims(param.kernel{i});
            end
            param.ndim{i} = 1:n;
        end
    end
    for i = 1:narg
        if isvector(param.kernel{i}) & isempty(param.ndim{i})
            param.kernel{i}(isnan(param.kernel{i})) = param.szarg{i}(isnan(param.kernel{i}));
        end
    end

    % stride validation
    if isempty(param.stride)
        param.stride = cellfun(@(x) ones(size(x)), param.kernel, 'UniformOutput', false);
    end
    if isa(param.stride, 'double')
        param.stride = repelem({param.stride}, narg);
    end
    if narg ~= numel(param.stride); error('`param.kernel` and `param.stride` dimensions must be equal'); end
    param.stride = cellfun(@(x) cast(x, param.cast), param.stride, 'UniformOutput', false);

    % offset validation
    if isempty(param.offset)
        param.offset = cellfun(@(x) zeros(size(x)), param.kernel, 'UniformOutput', false);
    end
    if isa(param.offset, 'double')
        param.offset = repelem({param.offset}, narg);
    end
    if narg ~= numel(param.offset); error('`param.kernel` and `param.offset` dimensions must be equal'); end
    param.offset = cellfun(@(x) cast(x, param.cast), param.offset, 'UniformOutput', false);

    % adjust kernel/stride/offset by given filter dimensions
    for i = 1:narg
        if isvector(param.kernel{i})
            if param.slice
                kernel = nan(1, numel(param.szarg{i}));
            else
                kernel = ones(1, numel(param.szarg{i}));
            end
            kernel(param.ndim{i}) = param.kernel{i};
            param.kernel{i} = kernel;
            param.kernel{i}(isnan(param.kernel{i})) = param.szarg{i}(isnan(param.kernel{i}));
        end

        if isvector(param.stride{i})
            stride = ones(1, numel(param.szarg{i}), param.cast);
            stride(param.ndim{i}) = param.stride{i};
            param.stride{i} = stride;
        end

        if isvector(param.offset{i})
            offset = zeros(1, numel(param.szarg{i}), param.cast);
            offset(param.ndim{i}) = param.offset{i};
            param.offset{i} = offset;
        end

        padval = num2cell(false(1, numel(param.szarg{i})));
        padval(param.ndim{i}) = [param.padval{i}(param.ndim{i})];
        param.padval{i} = padval;

        ispad = num2cell(false(1, numel(param.szarg{i})));
        ispad(param.ndim{i}) = [param.ispad{i}(param.ndim{i})];
        param.ispad{i} = ispad;
    end
    param.kernel = cellfun(@(x) cast(x, param.cast), param.kernel, 'UniformOutput', false);

    % evaluate a size of filtered data
    szfilt = cell(1, narg);
    for i = 1:narg
        if isvector(param.stride{i})
            for j = 1:ndimsarg{i}
                if isvector(param.kernel{i}) && ~param.ispad{i}{j}
                    temp = param.kernel{i}(j);
                    if mod(temp, 2) ~= 0; temp = temp - 1; end
                    szfilt{i}(j) = numel(1:param.stride{i}(j):param.szarg{i}(j)-temp);
                else
                    szfilt{i}(j) = numel(1:param.stride{i}(j):param.szarg{i}(j));
                end
            end
            szfilt{i}(szfilt{i} == 0) = 1;
        else
            szfilt{i} = size(param.stride{i}, 1:ndims(param.stride{i})-1);
        end
    end
    
    % check a consistency of filtered data size
    szfnumel = cell2mat(cellfun(@numel, szfilt, UniformOutput = false));
    if numel(unique(szfnumel)) ~= 1; error(strcat("inconsistent dimensions of filter `param.strides`: ", jsonencode(szfnumel))); end
    szfval = zeros(numel(szfilt), szfnumel(1));
    for i = 1:numel(szfilt); szfval(i,:) = szfilt{i}; end
    if ~isvector(unique(szfval, 'row')); error(strcat("inconsistent grid of filter `param.strides`: ", jsonencode(szfval))); end
    szfilt = szfilt{1};
    numfilt = prod(szfilt);

    % repeat vector elements according to size of filtered data 
    for i = 1:narg
        if isvector(param.kernel{i})
            arg = cat(2, {shiftdim(param.kernel{i}, -numel(param.kernel{i}))}, num2cell(szfilt));
            param.kernel{i} = repmat(arg{:});
        end
        if isvector(param.stride{i})
            arg = cat(2, {shiftdim(param.stride{i}, -numel(param.stride{i}))}, num2cell(szfilt));
            param.stride{i} = repmat(arg{:});
        end
        if isvector(param.offset{i})
            arg = cat(2, {shiftdim(param.offset{i}, -numel(param.offset{i}))}, num2cell(szfilt));
            param.offset{i} = repmat(arg{:});
        end
    end

    % shift dimensition
    for i = 1:narg
        param.kernel{i} = shiftdim(param.kernel{i}, ndims(param.kernel{i})-1);
        param.stride{i} = shiftdim(param.stride{i}, ndims(param.stride{i})-1);
        param.offset{i} = shiftdim(param.offset{i}, ndims(param.offset{i})-1);
    end

    % size validation
    for i = 1:narg
        if ndimsarg{i} < size(param.kernel{i}, 1); error('`param.kernel` dimension number must not exceed data dimension number'); end
        if size(param.kernel{i}) ~= size(param.stride{i}); error('`param.kernel` and `param.stride` dimensions must be equal'); end
        if size(param.kernel{i}) ~= size(param.offset{i}); error('`param.kernel` and `param.offset` dimensions must be equal'); end
    end

    % cumulate strides
    for i = 1:narg
        if param.strideisvector(i)
            for j = 1:size(param.stride{i}, 1)
                param.stride{i}(j,:) = reshape(cumsum(reshape(param.stride{i}(j,:), szfilt), j), [], 1)-param.stride{i}(j,1)+1;
            end
        else
            for j = 1:size(param.stride{i}, 1)
                param.stride{i}(j,:) = reshape(cumsum(reshape(param.stride{i}(j,:), szfilt), j), [], 1);
            end
        end
    end

    % shift stride by half kernel at enabled padding
    for i = 1:narg
        for j = 1:ndimsarg{i}
            if param.ispad{i}{j}
                temp = fix(param.kernel{i}(j,:)/2);
                temp(temp~=0) = temp(temp~=0) - 1;
                param.stride{i}(j,:) = param.stride{i}(j,:) - temp;
            end
        end
    end

    % substract one node from kernel
    for i = 1:narg
        param.kernel{i} = param.kernel{i} - 1;
        param.kernel{i}(param.kernel{i}<0) = 0;
    end
    
    % evaluate outbound index slices
    outbound = cell(1, narg);
    for i = 1:narg
        [minval, maxval] = bounds(reshape(cat(ndims(param.kernel{i}) + 1, zeros(size(param.kernel{i}), param.cast), ...
            param.kernel{i}) + param.stride{i} + param.offset{i}, [numel(param.szarg{i}), prod(szfilt), 2]), [2, 3]);
        outbound{i} = [minval, maxval];

        % evaluate paddings
        for j = 1:size(outbound{i}, 1)
            if param.ispad{i}{j}
                if outbound{i}(j, 1) < 1
                    outbound{i}(j, 1) = abs(outbound{i}(j, 1)) + 1;
                else
                    outbound{i}(j, 1) = 0;
                end
    
                if outbound{i}(j, 2) > param.szarg{i}(j)
                    outbound{i}(j, 2) = outbound{i}(j, 2) - param.szarg{i}(j);
                else
                    outbound{i}(j, 2) = 0;
                end
            else
                outbound{i}(j, :) = 0;
            end
        end
    end

    % shift origin indexes according to padding
    param.stride = cellfun(@(s,o,b) s+o+b(:, 1), param.stride, param.offset, ...
        outbound, 'UniformOutput', false);
    param.offset = [];

    % evaluate filter passing
    filtpass = [];
    if param.isfiltpass
        masks = cellfun(@(x) zeros(x, param.cast), param.szarg, UniformOutput = false);

        % padding of input data
        for i = 1:narg
            for j = 1:size(outbound{i}, 1)
                padsize = zeros(1, size(outbound{i}, 1));
                padsize(j) = outbound{i}(j, 1);    
                masks{i} = padarray(masks{i}, padsize, 1, 'pre');
    
                padsize = zeros(1, size(outbound{i}, 1));
                padsize(j) = outbound{i}(j, 2);       
                masks{i} = padarray(masks{i}, padsize, 1, 'post');
            end
        end

        poolobj = poolswitcher('backgroundPool', []);
        filtpass = cell(numfilt, 1);
        parfor (k = 1:numfilt, poolobj)
            dataslice = cell(1, narg);
            
            for i = 1:narg  
                kernel = param.kernel{i}(:,k);
                stride = param.stride{i}(:,k);
    
                temporary = arrayfun(@(k,s) (0:k)+s, kernel, stride, 'UniformOutput', false);
    
                tempfunc = masks{i};
                tempfunc(temporary{:}) = 3;
                dataslice{i} = tempfunc;
            end

            filtpass{k} = dataslice;
        end

    end

    results = struct;
    results.narg = narg;
    results.ndimsarg = ndimsarg;
    results.kernel = param.kernel;
    results.stride = param.stride;
    results.padval = param.padval;
    results.szfilt = szfilt;
    results.numfilt = numfilt;
    results.outbound = outbound;

    varargout{1} = results;
    varargout{2} = filtpass;

    if param.verbose; disp(strcat("filteval: elapsed time is ", num2str(toc(timer)), " seconds")); end

end