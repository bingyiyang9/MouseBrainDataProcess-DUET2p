function m = nanmedian(varargin)
if nargin==1, m=median(varargin{1},'omitnan'); else, m=median(varargin{1},varargin{2},'omitnan'); end
end
