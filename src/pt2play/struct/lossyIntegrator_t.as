package pt2play.struct 
{

public class lossyIntegrator_t 
{
    public var
        buffer:Vector.<Number>,        //float[2]
        coefficient:Vector.<Number>;   //float[2]
    
    
    public function lossyIntegrator_t() 
    {
        buffer = new Vector.<Number>(2, true);
        coefficient = new Vector.<Number>(2, true);
        //C inits floats to 0, AS3 inits to NaN
        buffer[0] = 0.0;
        buffer[1] = 0.0;
        coefficient[0] = 0.0;
        coefficient[1] = 0.0;
    }
    
}

}