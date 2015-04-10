package pt2play 
{

/*
** This file is part of the ProTracker v2.3D clone
** project by Olav "8bitbubsy" Sorensen.
**
** All of the files are considered 'public domain',
** do whatever you want with it.
**
*/

// thanks to aciddose/ad/adejr for the blep/cutoff/filter stuff!
// information on blep variables
//
// ZC = zero crossings, the number of ripples in the impulse
// OS = oversampling, how many samples per zero crossing are taken
// SP = step size per output sample, used to lower the cutoff (play the impulse slower)
// NS = number of samples of impulse to insert
// RNS = the lowest power of two greater than NS, minus one (used to wrap output buffer)
//
// ZC and OS are here only for reference, they depend upon the data in the table and can't be changed.
// SP, the step size can be any number lower or equal to OS, as long as the result NS remains an integer.
// for example, if ZC=8,OS=5, you can set SP=1, the result is NS=40, and RNS must then be 63.
// the result of that is the filter cutoff is set at nyquist * (SP/OS), in this case nyquist/5. 

public class Blep 
{
    [inline] private static const
    /* BLEP CONSTANTS */
    ZC:uint = 8,
    OS:uint = 5,
    SP:uint = 5,
    NS:uint = (ZC * OS / SP),
    RNS:uint = 7; // RNS = (2^ > NS) - 1
    
    private static const
    blepData:Vector.<Number> = Vector.<Number>([
         0.999541,  0.999348,  0.999369,  0.999342,
         0.998741,  0.996602,  0.991206,  0.979689,
         0.957750,  0.919731,  0.859311,  0.770949,
         0.651934,  0.504528,  0.337462,  0.165926,
         0.009528, -0.111687, -0.182304, -0.196163,
        -0.158865, -0.087007, -0.003989,  0.066445,
         0.106865,  0.110733,  0.083313,  0.038687,
        -0.005893, -0.036136, -0.045075, -0.034260,
        -0.011718,  0.012108,  0.028606,  0.033769,
         0.028673,  0.017904,  0.006982,  0.000000,
         0.000000,  0.000000,  0.000000,  0.000000,
         0.000000,  0.000000,  0.000000,  0.000000
    ]);
    
    public var
        samplesLeft:int,        //int32_t
        lastValue:Number;       //float
    private var
        index:int,              //int32_t
        buffer:Vector.<Number>; //float[RNS + 1]
    
    public function Blep() 
    {
        buffer = new Vector.<Number>(RNS + 1);
        //C inits floats to 0, AS3 inits to NaN
        for (var i:int = 0; i < buffer.length; i++) buffer[i] = 0.0;
        
        lastValue = 0;
    }
    
    public function blepAdd(offset:Number, amplitude:Number):void
    {
        var n:int;
        var i:uint;

        var src:uint;
        var f:Number;

        n   = NS;
        i   = offset * SP;
        src = i + OS;
        f   = (offset * SP) - i;
        i   = index;

        while (n--)
        {
            buffer[i] += (amplitude * (blepData[src + 0] + (blepData[src + 1] - blepData[src + 0]) * f));
            src         += SP;

            i++;
            i &= RNS;
        }

        samplesLeft = NS;
    }
    
    public function blepRun():Number
    {
        var output:Number;

        output            = buffer[index];
        buffer[index] = 0.0;

        index++;
        index &= RNS;

        samplesLeft--;

        return output;
    }
    
}

}