function data = lgraphReadData(filename,options)
arguments (Input)
    filename {mustBeFile}
    options.cast {mustBeMember(options.cast, {'single', 'double'})} = 'double'
end
arguments (Output)
    data (:,1) {mustBeA(data, {'single', 'double'})}
end
    fid = fopen(filename, 'r');
    data = fread(fid, 'int16');
    data = cast(data, options.cast);
    fclose(fid);
end