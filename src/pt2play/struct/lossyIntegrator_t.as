package pt2play.struct 
{

public class lossyIntegrator_t 
{
    public var
        buf0:Number,
        buf1:Number,
        coef0:Number,
        coef1:Number;
    
    
    public function lossyIntegrator_t(sr:Number, hz:Number) 
    {
        //C inits floats to 0, AS3 inits to NaN
        buf0 = 0.0;
        buf1 = 0.0;
        //coef0 = 0.0;
        //coef1 = 0.0;
        
        coef0 = Math.tan(Math.PI * hz / sr);
        coef1 = 1.0 / (1.0 + coef0);
    }

    public function clearLossyIntegrator():void
    {
        buf0 = 0.0;
        buf1 = 0.0;
    }
    
    [inline] final public function lossyIntegrator(vin:Vector.<Number>, vout:Vector.<Number>):void
    {
        var output:Number;
        var len:uint = vin.length / 2;
        for (var i:int = 0; i < len; i++) 
        {
            // left channel
            output      = (coef0 * vin[i*2+0] + buf0) * coef1;
            buf0        = coef0 * (vin[i*2+0] - output) + output + 1e-10;
            vout[i*2+0] = output;

            // right channel
            output      = (coef0 * vin[i*2+1] + buf1) * coef1;
            buf1        = coef0 * (vin[i*2+1] - output) + output + 1e-10;
            vout[i*2+1] = output; 
        }
    }

    [inline] final public function lossyIntegratorHighPass(vin:Vector.<Number>, vout:Vector.<Number>):void
    {
        var output:Number;
        var len:uint = vin.length / 2;
        for (var i:int = 0; i < len; i++) 
        {
            // left channel
            output      = (coef0 * vin[i*2+0] + buf0) * coef1;
            buf0        = coef0 * (vin[i*2+0] - output) + output + 1e-10;
            vout[i*2+0] = vin[i*2+0] - output;

            // right channel
            output      = (coef0 * vin[i*2+1] + buf1) * coef1;
            buf1        = coef0 * (vin[i*2+1] - output) + output + 1e-10;
            vout[i*2+1] = vin[i*2+1] - output; 
        }
    }
/*
[inline] final private function lossyIntegratorHighPass(vin:Vector.<Number>, vout:Vector.<Number>):void
{
    var low:Vector.<Number>; //float[2]

    lossyIntegrator(vin, low);

    vout[0] = vin[0] - low[0];
    vout[1] = vin[1] - low[1];
}
*/
    
}

}