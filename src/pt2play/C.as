package pt2play 
{

public class C 
{
    [inline] public static const NULL:uint = 0xFFFFFFFF;
    
    [inline] public static const
    INITIAL_STEREO_SEP_PERCENTAGE:uint = 50, /* stereo separation in percent */

    /* BLEP CONSTANTS */
    ZC:uint = 8,
    OS:uint = 0, //5
    SP:uint = 5,
    NS:uint = (ZC * OS / SP),
    RNS:uint = 7; // RNS = (2^ > NS) - 1
    
    /* TABLES */
    public static const
    
    mt_FunkTable:Vector.<uint> = Vector.<uint>([
        0x00, 0x05, 0x06, 0x07, 0x08, 0x0A, 0x0B, 0x0D,
        0x10, 0x13, 0x16, 0x1A, 0x20, 0x2B, 0x40, 0x80
    ]),

    mt_VibratoTable:Vector.<uint> = Vector.<uint>([
        0x00, 0x18, 0x31, 0x4A, 0x61, 0x78, 0x8D, 0xA1,
        0xB4, 0xC5, 0xD4, 0xE0, 0xEB, 0xF4, 0xFA, 0xFD,
        0xFF, 0xFD, 0xFA, 0xF4, 0xEB, 0xE0, 0xD4, 0xC5,
        0xB4, 0xA1, 0x8D, 0x78, 0x61, 0x4A, 0x31, 0x18
    ]),

    mt_PeriodDiffs:Vector.<int> = Vector.<int>([
          0,-48,-46,-42,-42,-38,-36,-34,-32,-30,-28,-27,-25,-24,-23,-21,-21,-19,
        -18,-17,-16,-15,-14,-14,-12,-12,-12,-10,-10,-10, -9, -8, -8, -8, -7, -7,
         -6,-48,-45,-42,-41,-37,-36,-34,-32,-30,-28,-27,-25,-24,-22,-22,-20,-19,
        -18,-16,-16,-15,-14,-14,-12,-12,-12,-10,-10,-10, -9, -8, -8, -8, -7, -6,
        -12,-48,-44,-43,-39,-38,-35,-34,-31,-30,-28,-27,-25,-24,-22,-21,-20,-19,
        -18,-16,-16,-15,-14,-13,-13,-12,-11,-11,-10, -9,- 9, -8, -8, -8, -7, -6,
        -18,-47,-45,-42,-39,-37,-36,-33,-31,-30,-28,-26,-25,-24,-22,-21,-20,-18,
        -18,-16,-16,-15,-14,-13,-13,-11,-11,-11,-10, -9, -9, -8, -8, -7, -7, -7,
        -24,-47,-44,-42,-39,-37,-35,-33,-31,-29,-28,-26,-25,-24,-22,-20,-20,-18,
        -18,-16,-16,-15,-14,-13,-12,-12,-11,-10,-10, -9, -9, -8, -8, -7, -7, -7,
        -30,-47,-43,-42,-39,-36,-35,-33,-31,-29,-28,-26,-24,-23,-22,-21,-19,-19,
        -17,-16,-16,-15,-13,-13,-13,-11,-11,-10,-10, -9, -9, -8, -8, -7, -7, -7,
        -36,-46,-44,-41,-38,-37,-34,-33,-31,-29,-27,-26,-24,-23,-22,-20,-20,-18,
        -17,-16,-16,-14,-14,-13,-12,-12,-10,-11, -9, -9, -9, -8, -8, -7, -7, -6,
        -42,-46,-43,-41,-38,-36,-35,-32,-30,-29,-27,-26,-24,-23,-21,-21,-19,-18,
        -17,-16,-16,-14,-14,-12,-12,-12,-11,-10,-10, -9, -8, -8, -8, -7, -7, -6,
         51,-51,-48,-46,-42,-42,-38,-36,-34,-32,-30,-28,-27,-25,-24,-23,-21,-21,
        -19,-18,-17,-16,-15,-14,-14,-12,-12,-12,-10,-10,-10, -9, -8, -8, -8, -7,
         44,-50,-48,-45,-42,-40,-39,-35,-34,-32,-30,-28,-27,-25,-24,-22,-22,-20,
        -19,-18,-16,-16,-15,-15,-13,-13,-12,-11,-10,-10,-10, -9, -8, -8, -8, -7,
         38,-50,-48,-44,-43,-39,-38,-35,-34,-31,-30,-28,-27,-25,-24,-22,-21,-20,
        -19,-18,-16,-16,-15,-14,-14,-12,-12,-11,-11,-10, -9, -9, -8, -8, -8, -7,
         31,-49,-47,-45,-42,-39,-37,-36,-33,-31,-30,-28,-26,-25,-24,-22,-21,-20,
        -18,-18,-16,-16,-15,-14,-13,-13,-11,-11,-11,-10, -9, -9, -8, -8, -7, -7,
         25,-49,-47,-44,-42,-39,-37,-35,-33,-31,-30,-27,-26,-25,-24,-22,-20,-20,
        -18,-18,-16,-16,-15,-14,-13,-12,-12,-11,-10,-10, -9, -9, -8, -8, -8, -6,
         19,-49,-47,-43,-42,-39,-36,-35,-33,-31,-29,-28,-26,-24,-23,-22,-21,-19,
        -19,-17,-16,-16,-15,-13,-13,-13,-11,-11,-10,-10, -9, -9, -8, -8, -7, -7,
         12,-48,-46,-44,-41,-38,-37,-34,-33,-31,-29,-27,-26,-24,-23,-22,-20,-20,
        -18,-17,-16,-16,-14,-14,-13,-12,-12,-10,-11, -9, -9, -9, -8, -8, -7, -7,
          6,-48,-46,-43,-41,-38,-36,-35,-32,-30,-29,-27,-26,-24,-23,-21,-21,-19,
        -18,-17,-16,-16,-14,-14,-12,-13,-11,-11,-10,-10, -9, -8, -8, -8, -7, -7
    ]),

    blepData:Vector.<uint> = Vector.<uint>([
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
    
    public function C() 
    {
        
    }
    
}

}