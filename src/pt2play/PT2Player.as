package pt2play 
{

import flash.events.SampleDataEvent;
import flash.media.Sound;
import flash.media.SoundChannel;
import flash.utils.ByteArray;
import flash.utils.Endian;
import pt2play.struct.*;

public class PT2Player 
{
    
    private var D:ByteArray;
    private var audioOut:Sound;
    private var sc:SoundChannel;
    
    /* VARIABLES */
    private var
        mt_Chan1temp:PT_CHN,
        mt_Chan2temp:PT_CHN,
        mt_Chan3temp:PT_CHN,
        mt_Chan4temp:PT_CHN,
        
        AUD:Vector.<PA_CHN>,
        mt_SampleStarts:Vector.<int>,
        
        soundBufferSize:int,            //int32_t 
        mt_TempoMode:int,               //int8_t  
        mt_SongPos:int,                 //int8_t  
        mt_PosJumpFlag:int,             //int8_t  
        mt_PBreakFlag:int,              //int8_t  
        mt_Enable:int,                  //int8_t  
        mt_PBreakPos:int,               //int8_t  
        mt_PattDelTime:int,             //int8_t  
        mt_PattDelTime2:int,            //int8_t  
        mt_LowMask:uint,                //uint8_t 
        mt_Counter:uint,                //uint8_t 
        mt_Speed:uint,                  //uint8_t 
        mt_PeriodTable:Vector.<int>,    //*int16_t 
        mt_PatternPos:uint,             //uint16_t
        mt_TimerVal:int,                //int32_t 
        mt_PattPosOff:uint,             //uint32_t
        mt_PattOff:uint,                //uint32_t
        
        blep:Vector.<BLEP>,
        blepVol:Vector.<BLEP>,
        
    /* pre-initialized variables */
        masterBufferL:Vector.<Number>     = null,   //*float
        masterBufferR:Vector.<Number>     = null,   //*float
        mixerBuffer:Vector.<int>          = null,   //*int8_t
        samplesLeft:int                   = 0,      //int32_t   /* must be signed */
        mixingMutex:int                   = 0,      //int8_t 
        isMixing:int                      = 0,      //int8_t 
        samplesPerFrame:uint              = 882,    //uint32_t
        bufferSize:uint                   = 4096,
        f_outputFreq:Number               = 44100;
    
/* MACROS */
    [inline] private final function mt_PaulaStop(i:uint):void {
        AUD[i].POS = 0;
        AUD[i].FRAC = 0.0;
        AUD[i].TRIGGER = 0;
    }
    [inline] private final function mt_PaulaStart(i:uint):void {
        AUD[i].POS = 0;
        AUD[i].FRAC = 0.0;
        AUD[i].TRIGGER = 1;
    }
    [inline] private final function mt_PaulaSetVol(i:uint, x:int):void {
        AUD[i].VOL = x * (1.0 / 64.0);
    }
    [inline] private final function mt_PaulaSetLen(i:uint, x:int):void {
        AUD[i].LEN = x << 1;
    }
    [inline] private final function mt_PaulaSetDat(i:uint, x:int):void {
        AUD[i].DAT = x;
    }
    [inline] private final function mt_PaulaSetLoop(i:uint, x:int, y:uint):void {
        if (x) AUD[i].REPDAT = x;
        AUD[i].REPLEN = y << 1;
    }
    [inline] private final function mt_PaulaSetPer(i:uint, x:int):void {
        if (x) AUD[i].DELTA = (3546895 / (x)) / f_outputFreq;
    }
    [inline] private final function mt_AmigaWord(x:uint):uint {
        return ((x << 8) | (x >> 8)) & 0xFFFF;
    }
    [inline] private final function r_uint16le(arr:ByteArray, off:uint):uint {
        return arr[off] + (arr[off + 1] << 8);
    }
    [inline] private final function w_uint16le(arr:ByteArray, off:uint, x:uint):void {
        arr[off + 0] = x;
        arr[off + 1] = x >> 8;
    }
    [inline] private final function r_uint32le(arr:ByteArray, off:uint):uint {
        return arr[off] + (arr[off + 1] << 8) + (arr[off + 2] << 16) + (arr[off + 3] << 24);
    }
    [inline] private final function sign8(b:int):int {
        if(b >= 128) b -= 256
        return b;
    }

    public function PT2Player()
    {
        //yuckies
        mt_Chan1temp = new PT_CHN();
        mt_Chan2temp = new PT_CHN();
        mt_Chan3temp = new PT_CHN();
        mt_Chan4temp = new PT_CHN();
        mt_Chan1temp.n_index = 0;
        mt_Chan2temp.n_index = 1;
        mt_Chan3temp.n_index = 2;
        mt_Chan4temp.n_index = 3;
        AUD = new Vector.<PA_CHN>(4, true);
        AUD[0] = new PA_CHN();
        AUD[1] = new PA_CHN();
        AUD[2] = new PA_CHN();
        AUD[3] = new PA_CHN();
        mt_SampleStarts = new Vector.<int>(31, true);
        blep = new Vector.<BLEP>(4, true);
        blep[0] = new BLEP();
        blep[1] = new BLEP();
        blep[2] = new BLEP();
        blep[3] = new BLEP();
        blepVol = new Vector.<BLEP>(4, true);
        blepVol[0] = new BLEP();
        blepVol[1] = new BLEP();
        blepVol[2] = new BLEP();
        blepVol[3] = new BLEP();
        masterBufferL = new Vector.<Number>;
        masterBufferR = new Vector.<Number>;
        
        mt_TimerVal     = (f_outputFreq * 125) / 50;
        samplesPerFrame = mt_TimerVal / 125;
        
        audioOut = new Sound();
        audioOut.addEventListener(SampleDataEvent.SAMPLE_DATA, audioLoop);
        sc = audioOut.play();
    }
    
    /* CODE START */
    private function blepAdd(b:BLEP, offset:Number, amplitude:Number):void
    {
        var n:int;
        var i:uint;

        var src:uint;
        var f:Number;

        n   = C.NS;
        i   = offset * C.SP;
        src = i + C.OS;
        f   = offset * C.SP - i;
        i   = b.index;

        while (n--)
        {
            b.buffer[i] += (amplitude * (C.blepData[src + 0] + (C.blepData[src + 1] - C.blepData[src + 0]) * f));
            src         += C.SP;

            i++;
            i &= C.RNS;
        }

        b.samplesLeft = C.NS;
    }
    
    private function blepRun(b:BLEP):Number
    {
        var output:Number;

        output            = b.buffer[b.index];
        b.buffer[b.index] = 0.0;

        b.index++;
        b.index &= C.RNS;

        b.samplesLeft--;

        return output;
    }
    
    private function mt_UpdateFunk(ch:PT_CHN):void
    {
        var funkspeed:int;

        funkspeed = ch.n_glissfunk >> 4;
        if (funkspeed > 0)
        {
            ch.n_funkoffset += C.mt_FunkTable[funkspeed];
            if (ch.n_funkoffset & 128)
            {
                ch.n_funkoffset = 0;

                //TODO: check
                if (ch.n_wavestart != C.NULL) /* added for safety reasons */
                {
                    if (++ch.n_wavestart >= (ch.n_loopstart + ch.n_replen))
                        ch.n_wavestart = ch.n_loopstart;

                    //TODO: check read int8 from ByteArray
                    D[ch.n_wavestart] = -1 - sign8(D[ch.n_wavestart]);
                }
            }
        }
    }
    
    private function mt_SetGlissControl(ch:PT_CHN):void
    {
        ch.n_glissfunk = (ch.n_glissfunk & 0xF0) | (ch.n_cmd & 0x000F);
    }

    private function mt_SetVibratoControl(ch:PT_CHN):void
    {
        ch.n_wavecontrol = (ch.n_wavecontrol & 0xF0) | (ch.n_cmd & 0x000F);
    }

    private function mt_SetFineTune(ch:PT_CHN):void
    {
        ch.n_finetune = ch.n_cmd & 0x000F;
    }
    
    private function mt_JumpLoop(ch:PT_CHN):void
    {
        if (!mt_Counter)
        {
            if (!(ch.n_cmd & 0x000F))
            {
                //TODO: check uint16 -> int8
                ch.n_pattpos = sign8(mt_PatternPos >> 4);
            }
            else
            {
                if (!ch.n_loopcount)
                {
                    ch.n_loopcount = ch.n_cmd & 0x000F;
                }
                else
                {
                    if (!--ch.n_loopcount) return;
                }

                mt_PBreakPos  = ch.n_pattpos;
                mt_PBreakFlag = 1;
            }
        }
    }
    
    private function mt_SetTremoloControl(ch:PT_CHN):void
    {
        ch.n_wavecontrol = ((ch.n_cmd & 0x000F) << 4) | (ch.n_wavecontrol & 0x0F);
    }
    
    private function mt_RetrigNote(ch:PT_CHN):void
    {
        if (ch.n_cmd & 0x000F)
        {
            if (!mt_Counter)
            {
                if (ch.n_note & 0x0FFF) return;
            }

            if (!(mt_Counter % (ch.n_cmd & 0x000F)))
            {
                mt_PaulaSetDat(ch.n_index, ch.n_start);
                mt_PaulaSetLen(ch.n_index, ch.n_length);
                mt_PaulaSetLoop(ch.n_index, ch.n_loopstart, ch.n_replen);
                mt_PaulaStart(ch.n_index);
            }
        }
    }
    
    private function mt_VolumeSlide(ch:PT_CHN):void
    {
        if (!((ch.n_cmd & 0x00FF) >> 4))
        {
            ch.n_volume -= (ch.n_cmd & 0x000F);
            if (ch.n_volume < 0) ch.n_volume = 0;
        }
        else
        {
            ch.n_volume += ((ch.n_cmd & 0x00FF) >> 4);
            if (ch.n_volume > 64) ch.n_volume = 64;
        }

        mt_PaulaSetVol(ch.n_index, ch.n_volume);
    }

    private function mt_VolumeFineUp(ch:PT_CHN):void
    {
        if (!mt_Counter)
        {
            ch.n_volume += (ch.n_cmd & 0x000F);
            if (ch.n_volume > 64) ch.n_volume = 64;

            mt_PaulaSetVol(ch.n_index, ch.n_volume);
        }
    }

    private function mt_VolumeFineDown(ch:PT_CHN):void
    {
        if (!mt_Counter)
        {
            ch.n_volume -= (ch.n_cmd & 0x000F);
            if (ch.n_volume < 0) ch.n_volume = 0;

            mt_PaulaSetVol(ch.n_index, ch.n_volume);
        }
    }
    
    private function mt_NoteCut(ch:PT_CHN):void
    {
        if (mt_Counter == (ch.n_cmd & 0x000F))
        {
            ch.n_volume = 0;
            mt_PaulaSetVol(ch.n_index, 0);
        }
    }

    private function mt_NoteDelay(ch:PT_CHN):void
    {
        if (mt_Counter == (ch.n_cmd & 0x000F))
        {
            if (ch.n_note)
            {
                mt_PaulaSetDat(ch.n_index, ch.n_start);
                mt_PaulaSetLen(ch.n_index, ch.n_length);
                mt_PaulaSetLoop(ch.n_index, ch.n_loopstart, ch.n_replen);
                mt_PaulaStart(ch.n_index);
            }
        }
    }

    private function mt_PatternDelay(ch:PT_CHN):void
    {
        if (!mt_Counter)
        {
            if (!mt_PattDelTime2)
                mt_PattDelTime = (ch.n_cmd & 0x000F) + 1;
        }
    }

    private function mt_FunkIt(ch:PT_CHN):void
    {
        if (!mt_Counter)
        {
            ch.n_glissfunk = ((ch.n_cmd & 0x000F) << 4) | (ch.n_glissfunk & 0x0F);

            if (ch.n_glissfunk & 0xF0)
                mt_UpdateFunk(ch);
        }
    }

    private function mt_PositionJump(ch:PT_CHN):void
    {
        mt_SongPos     = (ch.n_cmd & 0x00FF) - 1; /* 0xFF (B00) jumps to pat 0 */
        mt_PBreakPos   = 0;
        mt_PosJumpFlag = 1;
    }

    private function mt_VolumeChange(ch:PT_CHN):void
    {
        ch.n_volume = ch.n_cmd & 0x00FF;
        if (ch.n_volume > 64) ch.n_volume = 64;

        mt_PaulaSetVol(ch.n_index, ch.n_volume);
    }

    private function mt_PatternBreak(ch:PT_CHN):void
    {
        mt_PBreakPos = (((ch.n_cmd & 0x00FF) >> 4) * 10) + (ch.n_cmd & 0x000F);
        if (mt_PBreakPos > 63)
            mt_PBreakPos = 0;

        mt_PosJumpFlag = 1;
    }

    private function mt_SetSpeed(ch:PT_CHN):void
    {
        if (ch.n_cmd & 0x00FF)
        {
            mt_Counter = 0;

            if (mt_TempoMode || ((ch.n_cmd & 0x00FF) < 32)){
                mt_Speed = ch.n_cmd & 0x00FF;
            }else {
                //TODO: check int16 cast
                samplesPerFrame = (mt_TimerVal / (ch.n_cmd & 0x00FF));
            }
        }
    }
    
    private function mt_Arpeggio(ch:PT_CHN):void
    {
        var i:uint;
        var dat:uint;
        var ap:uint;    //*int16_t

        dat = mt_Counter % 3;
        if (!dat)
        {
            mt_PaulaSetPer(ch.n_index, ch.n_period);
        }
        else
        {
            if (dat == 1)
                dat = (ch.n_cmd & 0x00FF) >> 4;
            else if (dat == 2)
                dat = ch.n_cmd & 0x000F;

            ap = 36 * ch.n_finetune;
            for (i = 0; i < 36; ++i)
            {
                if (ch.n_period >= mt_PeriodTable[ap + i])
                {
                    mt_PaulaSetPer(ch.n_index, mt_PeriodTable[ap + i + dat]);
                    break;
                }
            }
        }
    }

    private function mt_PortaUp(ch:PT_CHN):void
    {
        ch.n_period -= ((ch.n_cmd & 0x00FF) & mt_LowMask);
        mt_LowMask = 0xFF;

        if ((ch.n_period & 0x0FFF) < 113)
        {
            ch.n_period &= 0xF000;
            ch.n_period |= 113;
        }

        mt_PaulaSetPer(ch.n_index, ch.n_period & 0x0FFF);
    }

    private function mt_PortaDown(ch:PT_CHN):void
    {
        ch.n_period += ((ch.n_cmd & 0x00FF) & mt_LowMask);
        mt_LowMask = 0xFF;

        if ((ch.n_period & 0x0FFF) > 856)
        {
            ch.n_period &= 0xF000;
            ch.n_period |= 856;
        }

        mt_PaulaSetPer(ch.n_index, ch.n_period & 0x0FFF);
    }

    private function mt_FinePortaUp(ch:PT_CHN):void
    {
        if (!mt_Counter)
        {
            mt_LowMask = 0x0F;
            mt_PortaUp(ch);
        }
    }

    private function mt_FinePortaDown(ch:PT_CHN):void
    {
        if (!mt_Counter)
        {
            mt_LowMask = 0x0F;
            mt_PortaDown(ch);
        }
    }
    
    private function mt_SetTonePorta(ch:PT_CHN):void
    {
        var i:uint;
        var pp:uint;    //*int16_t
        var note:uint;

        note    = ch.n_note & 0x0FFF;
        pp      = 36 * ch.n_finetune;

        i = 0;
        while (1)
        {
            if (note >= mt_PeriodTable[pp + i])
                break;

            if (++i >= 36)
            {
                i = 35;
                break;
            }
        }

        if ((ch.n_finetune & 8) && i) i--;

        ch.n_wantedperiod  = mt_PeriodTable[pp + i];
        ch.n_toneportdirec = 0;

        if (ch.n_period == ch.n_wantedperiod)
            ch.n_wantedperiod = 0;
        else if (ch.n_period > ch.n_wantedperiod)
            ch.n_toneportdirec = 1;
    }

    private function mt_TonePortNoChange(ch:PT_CHN):void
    {
        var i:uint;
        var pp:uint;    //*int16_t

        if (ch.n_wantedperiod)
        {
            if (ch.n_toneportdirec)
            {
                ch.n_period -= ch.n_toneportspeed;
                if (ch.n_period <= ch.n_wantedperiod)
                {
                    ch.n_period       = ch.n_wantedperiod;
                    ch.n_wantedperiod = 0;
                }
            }
            else
            {
                ch.n_period += ch.n_toneportspeed;
                if (ch.n_period >= ch.n_wantedperiod)
                {
                    ch.n_period       = ch.n_wantedperiod;
                    ch.n_wantedperiod = 0;
                }
            }

            if (!(ch.n_glissfunk & 0x0F))
            {
                mt_PaulaSetPer(ch.n_index, ch.n_period);
            }
            else
            {
                pp = 36 * ch.n_finetune;

                i = 0;
                while (1)
                {
                    if (ch.n_period >= mt_PeriodTable[pp + i])
                        break;

                    if (++i >= 36)
                    {
                        i = 35;
                        break;
                    }
                }

                mt_PaulaSetPer(ch.n_index, mt_PeriodTable[pp + i]);
            }
        }
    }

    private function mt_TonePortamento(ch:PT_CHN):void
    {
        if (ch.n_cmd & 0x00FF)
        {
            ch.n_toneportspeed = ch.n_cmd & 0x00FF;
            ch.n_cmd &= 0xFF00;
        }

        mt_TonePortNoChange(ch);
    }

    private function mt_VibratoNoChange(ch:PT_CHN):void
    {
        var vibratoTemp:uint;
        var vibratoData:int;

        vibratoTemp = (ch.n_vibratopos >> 2) & 0x1F;
        vibratoData =  ch.n_wavecontrol      & 0x03;

        if (!vibratoData)
        {
            vibratoData = C.mt_VibratoTable[vibratoTemp];
        }
        else
        {
            if (vibratoData == 1)
            {
                if (ch.n_vibratopos < 0)
                    vibratoData = 255 - (vibratoTemp << 3);
                else
                    vibratoData = vibratoTemp << 3;
            }
            else
            {
                vibratoData = 255;
            }
        }

        vibratoData = (vibratoData * (ch.n_vibratocmd & 0x0F)) >> 7;

        if (ch.n_vibratopos < 0)
            vibratoData = ch.n_period - vibratoData;
        else
            vibratoData = ch.n_period + vibratoData;

        mt_PaulaSetPer(ch.n_index, vibratoData);

        ch.n_vibratopos += ((ch.n_vibratocmd >> 2) & 0x3C);
    }

    private function mt_Vibrato(ch:PT_CHN):void
    {
        if (ch.n_cmd & 0x00FF)
        {
            if (ch.n_cmd & 0x000F)
                ch.n_vibratocmd = (ch.n_vibratocmd & 0xF0) | (ch.n_cmd & 0x000F);

            if (ch.n_cmd & 0x00F0)
                ch.n_vibratocmd = (ch.n_cmd & 0x00F0) | (ch.n_vibratocmd & 0x0F);
        }

        mt_VibratoNoChange(ch);
    }

    private function mt_TonePlusVolSlide(ch:PT_CHN):void
    {
        mt_TonePortNoChange(ch);
        mt_VolumeSlide(ch);
    }

    private function mt_VibratoPlusVolSlide(ch:PT_CHN):void
    {
        mt_VibratoNoChange(ch);
        mt_VolumeSlide(ch);
    }

    private function mt_Tremolo(ch:PT_CHN):void
    {
        var tremoloTemp:int;
        var tremoloData:int;

        if (ch.n_cmd & 0x00FF)
        {
            if (ch.n_cmd & 0x000F)
                ch.n_tremolocmd = (ch.n_tremolocmd & 0xF0) | (ch.n_cmd & 0x000F);

            if (ch.n_cmd & 0x00F0)
                ch.n_tremolocmd = (ch.n_cmd & 0x00F0) | (ch.n_tremolocmd & 0x0F);
        }

        tremoloTemp = (ch.n_tremolopos  >> 2) & 0x1F;
        tremoloData = (ch.n_wavecontrol >> 4) & 0x03;

        if (!tremoloData)
        {
            tremoloData = C.mt_VibratoTable[tremoloTemp];
        }
        else
        {
            if (tremoloData == 1)
            {
                if (ch.n_vibratopos < 0) /* PT bug, but don't fix this one */
                    tremoloData = 255 - (tremoloTemp << 3);
                else
                    tremoloData = tremoloTemp << 3;
            }
            else
            {
                tremoloData = 255;
            }
        }

        tremoloData = (tremoloData * (ch.n_tremolocmd & 0x0F)) >> 6;

        if (ch.n_tremolopos < 0)
        {
            tremoloData = ch.n_volume - tremoloData;
            if (tremoloData < 0) tremoloData = 0;
        }
        else
        {
            tremoloData = ch.n_volume + tremoloData;
            if (tremoloData > 64) tremoloData = 64;
        }

        mt_PaulaSetVol(ch.n_index, tremoloData);

        ch.n_tremolopos += ((ch.n_tremolocmd >> 2) & 0x3C);
    }
    
    private function mt_SampleOffset(ch:PT_CHN):void
    {
        var newOffset:uint;

        if (ch.n_cmd & 0x00FF)
            ch.n_sampleoffset = ch.n_cmd & 0x00FF;

        newOffset = ch.n_sampleoffset << 7;
        if (newOffset < ch.n_length)
        {
            ch.n_length -=  newOffset;
            ch.n_start  += (newOffset << 1);
        }
        else
        {
            ch.n_length = 1;
        }
    }

    private function mt_E_Commands(ch:PT_CHN):void
    {
        switch ((ch.n_cmd & 0x00F0) >> 4)
        {
            case 0x00: break;
            case 0x01: mt_FinePortaUp(ch);       break;
            case 0x02: mt_FinePortaDown(ch);     break;
            case 0x03: mt_SetGlissControl(ch);   break;
            case 0x04: mt_SetVibratoControl(ch); break;
            case 0x05: mt_SetFineTune(ch);       break;
            case 0x06: mt_JumpLoop(ch);          break;
            case 0x07: mt_SetTremoloControl(ch); break;
            case 0x08: break;
            case 0x09: mt_RetrigNote(ch);        break;
            case 0x0A: mt_VolumeFineUp(ch);      break;
            case 0x0B: mt_VolumeFineDown(ch);    break;
            case 0x0C: mt_NoteCut(ch);           break;
            case 0x0D: mt_NoteDelay(ch);         break;
            case 0x0E: mt_PatternDelay(ch);      break;
            case 0x0F: mt_FunkIt(ch);            break;
        }
    }

    private function mt_CheckMoreEfx(ch:PT_CHN):void
    {
        switch ((ch.n_cmd >> 8) & 0x0F)
        {
            case 0x09: mt_SampleOffset(ch); break;
            case 0x0B: mt_PositionJump(ch); break;
            case 0x0C: mt_VolumeChange(ch); break;
            case 0x0D: mt_PatternBreak(ch); break;
            case 0x0E: mt_E_Commands(ch);   break;
            case 0x0F: mt_SetSpeed(ch);     break;

            default: mt_PaulaSetPer(ch.n_index, ch.n_period); break;
        }
    }

    private function mt_CheckEfx(ch:PT_CHN):void
    {
        mt_UpdateFunk(ch);

        if (ch.n_cmd & 0x0FFF)
        {
            switch ((ch.n_cmd >> 8) & 0x0F)
            {
                case 0x00: mt_Arpeggio(ch);            break;
                case 0x01: mt_PortaUp(ch);             break;
                case 0x02: mt_PortaDown(ch);           break;
                case 0x03: mt_TonePortamento(ch);      break;
                case 0x04: mt_Vibrato(ch);             break;
                case 0x05: mt_TonePlusVolSlide(ch);    break;
                case 0x06: mt_VibratoPlusVolSlide(ch); break;
                case 0x0E: mt_E_Commands(ch);          break;
                case 0x07:
                    mt_PaulaSetPer(ch.n_index, ch.n_period);
                    mt_Tremolo(ch);
                break;
                case 0x0A:
                    mt_PaulaSetPer(ch.n_index, ch.n_period);
                    mt_VolumeSlide(ch);
                break;

                default: mt_PaulaSetPer(ch.n_index, ch.n_period); break;
            }
        }
        else
        {
            mt_PaulaSetPer(ch.n_index, ch.n_period);
        }
    }
    
    private function mt_SetPeriod(ch:PT_CHN):void
    {
        var i:uint;
        var note:uint;

        note = ch.n_note & 0x0FFF;
        for (i = 0; i < 36; ++i)
        {
            if (note >= mt_PeriodTable[i]) break;
        }

        if ((i == 36) && (ch.n_finetune == 15)) i = 35; /* non-PT access violation fix */

        ch.n_period = mt_PeriodTable[(36 * ch.n_finetune) + i];

        if ((ch.n_cmd & 0x0FF0) != 0x0ED0) /* no note delay */
        {
            if (!(ch.n_wavecontrol & 0x04)) ch.n_vibratopos = 0;
            if (!(ch.n_wavecontrol & 0x40)) ch.n_tremolopos = 0;

            mt_PaulaSetDat(ch.n_index, ch.n_start);
            mt_PaulaSetLen(ch.n_index, ch.n_length);
            mt_PaulaSetPer(ch.n_index, ch.n_period);
            mt_PaulaStart(ch.n_index);
        }

        mt_CheckMoreEfx(ch);
    }

    private function mt_PlayVoice(ch:PT_CHN):void
    {
        var pattData:Vector.<uint>;
        var sample:uint;
        var cmd:uint;
        var sampleOffset:uint;
        var repeat:uint;

        /* no channel data on this row */
        if (ch.n_note == 0 && ch.n_cmd == 0) mt_PaulaSetPer(ch.n_index, ch.n_period);

        pattData = new Vector.<uint>(4, true);
        pattData[0] = D[mt_PattPosOff + 0];
        pattData[1] = D[mt_PattPosOff + 1];
        pattData[2] = D[mt_PattPosOff + 2];
        pattData[3] = D[mt_PattPosOff + 3];

        mt_PattPosOff += 4;

        ch.n_note  = (pattData[0] << 8) | pattData[1];
        ch.n_cmd   = (pattData[2] << 8) | pattData[3];

        sample = (pattData[0] & 0xF0) | ((pattData[2] & 0xF0) >> 4);
        if (sample && (sample <= 32)) /* BUGFIX: don't do samples >31 */
        {
            sample--;
            sampleOffset = 42 + (30 * sample);

            ch.n_start    = mt_SampleStarts[sample];
            ch.n_finetune = D[sampleOffset + 2];
            ch.n_volume   = D[sampleOffset + 3];
            
            
            ch.n_length   = r_uint16le(D, sampleOffset + 0);
            ch.n_replen   = r_uint16le(D, sampleOffset + 6);

            repeat = r_uint16le(D, sampleOffset + 4);
            if (repeat > 0)
            {
                ch.n_loopstart = ch.n_start + (repeat << 1);
                ch.n_wavestart = ch.n_loopstart;
                ch.n_length    = repeat + ch.n_replen;
            }
            else
            {
                ch.n_loopstart = ch.n_start;
                ch.n_wavestart = ch.n_start;
            }
        }

        if (ch.n_note & 0x0FFF)
        {
            if ((ch.n_cmd & 0x0FF0) == 0x0E50) /* set finetune */
            {
                mt_SetFineTune(ch);
                mt_SetPeriod(ch);
            }
            else
            {
                cmd = (ch.n_cmd >> 8) & 0x0F;
                if ((cmd == 0x03) || (cmd == 0x05))
                {
                    mt_SetTonePorta(ch);
                    mt_CheckMoreEfx(ch);
                }
                else if (cmd == 0x09)
                {
                    mt_CheckMoreEfx(ch);
                    mt_SetPeriod(ch);
                }
                else
                {
                    mt_SetPeriod(ch);
                }
            }
        }
        else
        {
            mt_CheckMoreEfx(ch);
        }
    }

    [inline] private function mt_NextPosition():void
    {
        //TODO: check uint16 cast
        mt_PatternPos  = (mt_PBreakPos << 4) & 0xFFFF;
        mt_PBreakPos   = 0;
        mt_PosJumpFlag = 0;

        mt_SongPos = (mt_SongPos + 1) & 0x7F;
        if (mt_SongPos >= D[950])
            mt_SongPos = 0;

        //mt_PattOff = 1084 + ((uint32_t)(mt_SongDataPtr[952 + mt_SongPos]) << 10);
        mt_PattOff = 1084 + r_uint32le(D, 952 + mt_SongPos) << 10;
    }

    private function mt_MusicIRQ():void
    {
        mt_Counter++;
        if (mt_Counter >= mt_Speed)
        {
            mt_Counter = 0;

            if (!mt_PattDelTime2)
            {
                mt_PattPosOff = mt_PattOff + mt_PatternPos;

                mt_PlayVoice(mt_Chan1temp);
                mt_PaulaSetVol(0, mt_Chan1temp.n_volume);

                mt_PlayVoice(mt_Chan2temp);
                mt_PaulaSetVol(1, mt_Chan2temp.n_volume);

                mt_PlayVoice(mt_Chan3temp);
                mt_PaulaSetVol(2, mt_Chan3temp.n_volume);

                mt_PlayVoice(mt_Chan4temp);
                mt_PaulaSetVol(3, mt_Chan4temp.n_volume);

                mt_PaulaSetLoop(0, mt_Chan1temp.n_loopstart, mt_Chan1temp.n_replen);
                mt_PaulaSetLoop(1, mt_Chan2temp.n_loopstart, mt_Chan2temp.n_replen);
                mt_PaulaSetLoop(2, mt_Chan3temp.n_loopstart, mt_Chan3temp.n_replen);
                mt_PaulaSetLoop(3, mt_Chan4temp.n_loopstart, mt_Chan4temp.n_replen);
            }
            else
            {
                mt_CheckEfx(mt_Chan1temp);
                mt_CheckEfx(mt_Chan2temp);
                mt_CheckEfx(mt_Chan3temp);
                mt_CheckEfx(mt_Chan4temp);
            }

            mt_PatternPos += 16;

            if (mt_PattDelTime)
            {
                mt_PattDelTime2 = mt_PattDelTime;
                mt_PattDelTime = 0;
            }

            if (mt_PattDelTime2)
            {
                mt_PattDelTime2--;
                if (mt_PattDelTime2) mt_PatternPos -= 16;
            }

            if (mt_PBreakFlag)
            {
                mt_PatternPos = mt_PBreakPos << 4;
                mt_PBreakPos = 0;
                mt_PBreakFlag = 0;
            }

            if ((mt_PatternPos >= 1024) || mt_PosJumpFlag)
                mt_NextPosition();
        }
        else
        {
            mt_CheckEfx(mt_Chan1temp);
            mt_CheckEfx(mt_Chan2temp);
            mt_CheckEfx(mt_Chan3temp);
            mt_CheckEfx(mt_Chan4temp);

            if (mt_PosJumpFlag) mt_NextPosition();
        }
    }
    
    public function mt_Init(mt_Data:ByteArray):void
    {
        //TODO: reinstate duplication
        mt_Data.position = 0;
        D = mt_Data;
        //D = new ByteArray();
        D.endian = Endian.LITTLE_ENDIAN;
        //D.writeBytes(mt_Data, 0, mt_Data.length); //clone it for less headaches
        mt_Data.position = 0;
        
        var sampleStarts:uint;      //*uint8_t
        var pattNum:int;
        var i:uint;
        var p:uint;                 //*uint16_t
        var j:uint;
        var lastPeriod:uint;

        pattNum = 0;
        for (i = 0; i < 128; ++i)
        {
            if (D[952 + i] > pattNum)
                pattNum = D[952 + i];
        }
        pattNum++;

        sampleStarts = D[1084 + (pattNum << 10)];
        for (i = 0; i < 31; ++i)
        {
            //TODO: check cast from uint8 to int8
            mt_SampleStarts[i] = sign8(sampleStarts);
            p = 42 + (30 * i);//uint16_t *

            //TODO: fuck bubsy's swap, read big endian where needed
            /* swap bytes in words (Amiga word -> Intel word) */
            w_uint16le(D, p + 0, mt_AmigaWord(r_uint16le(D, p + 0))); /* n_length */
            w_uint16le(D, p + 2, mt_AmigaWord(r_uint16le(D, p + 2))); /* n_repeat */
            w_uint16le(D, p + 3, mt_AmigaWord(r_uint16le(D, p + 3))); /* n_replen */

            sampleStarts += r_uint16le(D, p + 0) << 1;
        }

        /*
        ** +14 for 14 extra zeroes to prevent access violation on -1
        ** (15 unsigned) finetuned samples with B-3 >+1 note arpeggios.
        ** PT was never bug free. :-)
        */
        mt_PeriodTable = null;
        
        mt_PeriodTable = new Vector.<int>(((36 * 16) + 14) * 2, true);
        for (i = 0; i < 16; ++i)
        {
            lastPeriod = 856;
            for (j = 0; j < 36; ++j)
                lastPeriod = mt_PeriodTable[(36 * i) + j] = lastPeriod
                    + C.mt_PeriodDiffs[(36 * i) + j];
        }

        mt_Speed        = 6;
        mt_Counter      = 0;
        mt_SongPos      = 0;
        mt_PatternPos   = 0;
        mt_Enable       = 0;
        mt_PattDelTime  = 0;
        mt_PattDelTime2 = 0;
        mt_PBreakPos    = 0;
        mt_PosJumpFlag  = 0;
        mt_PBreakFlag   = 0;
        mt_LowMask      = 0xFF;
        mt_PattOff      = 1084 + r_uint32le(D, D[952] << 10);
    }

    [inline] private function sinApx(x:Number):Number
    {
        x = x * (2.0 - x);
        return (x * 1.09742972 + x * x * 0.31678383);
    }
    [inline] private function cosApx(x:Number):Number
    {
        x = (1.0 - x) * (1.0 + x);
        return (x * 1.09742972 + x * x * 0.31678383);
    }

    private function mt_genPans(stereoSeparation:uint):void
    {
        var scaledPanPos:uint;

        var p:Number;

        scaledPanPos = (stereoSeparation << 7) / 100;

        p = (128 - scaledPanPos) * (1.0 / 256.0);
        AUD[0].PANL = cosApx(p);
        AUD[0].PANR = sinApx(p);
        AUD[3].PANL = cosApx(p);
        AUD[3].PANR = sinApx(p);

        p = (128 + scaledPanPos) * (1.0 / 256.0);
        AUD[1].PANL = cosApx(p);
        AUD[1].PANR = sinApx(p);
        AUD[2].PANL = cosApx(p);
        AUD[2].PANR = sinApx(p);
    }
    
    private function mixSampleBlock(streamOut:ByteArray, numSamples:uint):void
    {
        var i:uint;
        var sndOut:ByteArray;
        var j:uint;

        var tempSample:Number;
        var tempVolume:Number;
        var L:Number;
        var R:Number;

        var v:PA_CHN;
        var bSmp:BLEP;
        var bVol:BLEP;

        masterBufferL.length = numSamples;
        masterBufferR.length = numSamples;
        for (i = 0; i < numSamples; i++) 
        {
            masterBufferL[i] = 0.0;
            masterBufferR[i] = 0.0; 
        }

        for (i = 0; i < 4; ++i)
        {
            v = AUD[i];
            bSmp = blep[i];
            bVol = blepVol[i];

            //TODO: fix TRIGGER 0 and v.DAT NULL, always
            if (v.TRIGGER && v.DAT != C.NULL)
            {
                j = 0;
                for (; j < numSamples; ++j)
                {
                    tempSample = D[v.DAT + v.POS] * (1.0 / 128.0);
                    tempVolume = v.VOL;

                    if (tempSample != bSmp.lastValue)
                    {
                        if ((v.LASTDELTA > 0.0) && (v.LASTDELTA > v.LASTFRAC))
                            blepAdd(bSmp, v.LASTFRAC / v.LASTDELTA, bSmp.lastValue - tempSample);

                        bSmp.lastValue = tempSample;
                    }

                    if (tempVolume != bVol.lastValue)
                    {
                        blepAdd(bVol, 0.0, bVol.lastValue - tempVolume);
                        bVol.lastValue = tempVolume;
                    }

                    if (bSmp.samplesLeft) tempSample += blepRun(bSmp);
                    if (bVol.samplesLeft) tempVolume += blepRun(bVol);

                    tempSample *= tempVolume;
                    masterBufferL[j] += (tempSample * v.PANL);
                    masterBufferR[j] += (tempSample * v.PANR);

                    v.FRAC += v.DELTA;
                    if (v.FRAC >= 1.0)
                    {
                        v.POS++;
                        v.FRAC -= 1.0;

                        v.LASTFRAC  = v.FRAC;
                        v.LASTDELTA = v.DELTA;

                        if (v.POS >= v.LEN)
                        {
                            if (v.REPLEN > 2)
                            {
                                v.DAT  = v.REPDAT;
                                v.POS -= v.LEN;
                                v.LEN  = v.REPLEN;
                            }
                            else
                            {
                                v.POS     = 0;
                                v.TRIGGER = 0;

                                if (bSmp.lastValue != 0.0)
                                {
                                    if ((v.LASTDELTA > 0.0) && (v.LASTDELTA > v.LASTFRAC))
                                        blepAdd(bSmp, v.LASTFRAC / v.LASTDELTA, bSmp.lastValue);

                                    bSmp.lastValue = 0.0;
                                }

                                break;
                            }
                        }
                    }
                }

                if ((j < numSamples) && !v.TRIGGER && (bSmp.samplesLeft || bVol.samplesLeft))
                {
                    for (; j < numSamples; ++j)
                    {
                        tempSample = bSmp.lastValue;
                        tempVolume = bVol.lastValue;

                        if (bSmp.samplesLeft) tempSample += blepRun(bSmp);
                        if (bVol.samplesLeft) tempVolume += blepRun(bVol);

                        tempSample    *= tempVolume;
                        masterBufferL[j] += (tempSample * v.PANL);
                        masterBufferR[j] += (tempSample * v.PANR);
                    }
                }
            }
        }

        sndOut = streamOut;
        for (j = 0; j < numSamples; ++j)
        {
            if (!mt_Enable)
            {
                sndOut.writeFloat(0);
                sndOut.writeFloat(0);
            }
            else
            {
                //TODO: Redundancy removal
                L = masterBufferL[j] * (-32767.0 / 3.0);
                R = masterBufferR[j] * (-32767.0 / 3.0);

                if      (L < -32768.0) L = -32768.0;
                else if (L >  32767.0) L =  32767.0;
                if      (R < -32768.0) R = -32768.0;
                else if (R >  32767.0) R =  32767.0;

                sndOut.writeFloat(L/32768);
                sndOut.writeFloat(R/32768);
            }
        }
    }
    
    public function pt2play_PauseSong(pause:int):void
    {
        mt_Enable = pause ? 0 : 1;
    }

    public function pt2play_PlaySong(moduleData:ByteArray, tempoMode:int):void
    {
        mt_Init(moduleData);
        mt_genPans(C.INITIAL_STEREO_SEP_PERCENTAGE);

        
        
        mt_TempoMode = tempoMode ? 1 : 0; /* 0 = cia, 1 = vblank */
        mt_Enable    = 1;
    }

    public function pt2play_SetStereoSep(percentage:uint):void
    {
        mt_genPans(percentage);
    }
    
    
    private function audioLoop(event:SampleDataEvent):void
    {
        var sampleBlock:int;
        var samplesTodo:int; /* must be signed */
        
        sampleBlock = bufferSize;
        
        while (sampleBlock)
        {
            samplesTodo = (sampleBlock < samplesLeft) ? sampleBlock : samplesLeft;
            if (samplesTodo > 0)
            {
                mixSampleBlock(event.data, samplesTodo);
                
                sampleBlock   -= samplesTodo;
                samplesLeft   -= samplesTodo;
            }
            else
            {
                if (mt_Enable)
                    mt_MusicIRQ();

                samplesLeft = samplesPerFrame;
            }
        }
        
    }
    
}

}