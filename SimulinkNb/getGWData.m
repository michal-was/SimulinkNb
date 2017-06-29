function data = getGWData(chanList, start, duration, ffl)
%GETGWDATA  Fetch data from NDS server or Virgo frames
%
%   Syntax:
%
%   data = getGWData(chanList, start, duration, ffl)
%
%   Description:
%
%   getGWData(CHANLIST, START, DURATION) uses the GWData library to obtain
%   data from an NDS1 or NDS2 server.  Or it calls getVirgoData for V1
%   channels, if ffl provided uses that otherwise defaults to raw.
%
%   See also: GWDATA

% find which channels are for Virgo
virgoChannels = ~cellfun(@isempty, regexp(chanList, '^V1:.*'));
if all(virgoChannels)
  % if all channels are from Virgo use getVirgoData
  % FIXME: hard-coded using raw_full frames
  if nargin < 4
    data = getVirgoData(chanList, 'raw', start, duration);
  else
    data = getVirgoData(chanList, ffl, start, duration);
  end
else
  % use NDS for all channels if any LIGO channels is requested
  gwd = GWData();
  data = gwd.fetch(start, duration, chanList, 'mDV');
end

end
