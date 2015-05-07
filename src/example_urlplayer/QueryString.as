package example_urlplayer
{
    import flash.external.*;

    public class QueryString
    {
        private var _queryString:String;
        private var _all:String;
        private var _params:Object;
        private var _paramNum:uint;

        public function QueryString(url:String='')
        {
            readQueryString(url);
        }
        public function get getQueryString():String
        {
            return _queryString;
        }
        public function get url():String
        {
            return _all;
        }
        public function get parameters():Object
        {
            return _params;
        }
        public function get paramNum():uint
        {
            return _paramNum;
        }   

        private function readQueryString(url:String=''):void
        {
            _params = new Object();
            try
            {
                _all = (url.length > 0) ? url : ExternalInterface.call("window.location.href.toString");
                _queryString = (url.length > 0) ? url.split("?")[1] : ExternalInterface.call("window.location.search.substring", 1);
                if(_queryString)
                {
                    var allParams:Array = _queryString.split('&');
                    _paramNum = allParams.length;

                    for(var i:int=0, index:int=-1; i < allParams.length; i++)
                    {
                        var keyValuePair:String = allParams[i];
                        if((index = keyValuePair.indexOf("=")) > 0)
                        {
                            var paramKey:String = keyValuePair.substring(0,index).toLowerCase();
                            var paramValue:String = keyValuePair.substring(index + 1);
                            _params[paramKey] = unescape(paramValue);
                        }
                    }
                }
            }
            catch(e:Error)
            {
                trace("Some error occured. ExternalInterface doesn't work in Standalone player.");
                throw e;
            }
        }
    }
}