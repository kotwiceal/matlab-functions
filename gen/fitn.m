function f = fitn(varargin, options)
    %% Multidimensional fitting
    arguments (Input, Repeating)
        varargin 
    end
    arguments (Input)
        options.method {mustBeMember(options.method, {'linear', 'nearest', 'natural', 'cubic', 'v4'})} = 'linear'
    end
    arguments (Output)
        f function_handle
    end
    p = varargin(1:end-1);
    v = varargin{end};
    f = @(varargin)interpn(p{:},v,varargin{:},options.method);
end