/*
** PT2PLAY v1.0 - 7th of May 2015 - http://16-bits.org
** ===================================================
**
** C port of ProTracker 2.3A's replayer, by 8bitbubsy (Olav Sørensen)
** using the original asm source codes by Crayon (Peter Hanning) and ZAP (Lars Hamre)
**
** The only differences is that InvertLoop (EFx) is handled like the tracker replayer,
** since it sounds different in the replayer version bundled with the PT source codes.
**
** Even the mixer is written to do looping the way Paula (Amiga DSP) does.
** The BLEP (band-limited step) and high-pass filter routines were coded by aciddose/adejr.
**
** pt2play must not be confused with ptplay by Ronald Hof, Timm S. Mueller and Per Johansson.
** I guess I was a bit unlucky with my replayer naming scheme, sorry!
**
** This is by no means a piece of beautiful code, nor is it meant to be...
** It's just an accurate ProTracker 2.3A replayer port for people to enjoy.
**
*/

package pt2play 
{

import flash.events.SampleDataEvent;
import flash.media.Sound;
import flash.media.SoundChannel;
import flash.utils.ByteArray;
import flash.utils.Endian;
import pt2play.struct.*;
import debug.T;

public class PT2Player 
{
    public var amigaFilter:Boolean = false;
    
    private var D:Vector.<uint>;
    private var audioOut:Sound;
    private var sc:SoundChannel;
    
    /* VARIABLES */
    private var
        mt_ChanTemp:Vector.<PT_CHN>,
        
        AUD:Vector.<PA_CHN>,
        mt_SampleStarts:Vector.<int>,
        
        filterHi:lossyIntegrator_t,
        filterLo:lossyIntegrator_t,
        
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
        
        blep:Vector.<Blep>,
        blepVol:Vector.<Blep>,
        
    /* pre-initialized variables */
        masterBuffer:Vector.<Number>      = null,   //*float
        mixerBuffer:Vector.<int>          = null,   //*int8_t
        samplesLeft:int                   = 0,      //int32_t   /* must be signed */
        mixingMutex:int                   = 0,      //int8_t 
        isMixing:int                      = 0,      //int8_t 
        samplesPerFrame:uint              = 882,    //uint32_t
        bufferSize:uint                   = 4096,
        f_outputFreq:Number               = 44100;
    
/* MACROS */
    [inline] final private function mt_PaulaStop(i:uint):void {
        AUD[i].POS = 0;
        AUD[i].FRAC = 0.0;
        AUD[i].TRIGGER = 0;
    }
    [inline] final private function mt_PaulaStart(i:uint):void {
        AUD[i].POS = 0;
        AUD[i].FRAC = 0.0;
        AUD[i].TRIGGER = 1;
    }
    [inline] final private function mt_PaulaSetVol(i:uint, x:int):void {
        AUD[i].VOL = x * (1.0 / 64.0);
    }
    [inline] final private function mt_PaulaSetLen(i:uint, x:int):void {
        AUD[i].LEN = x << 1;
    }
    [inline] final private function mt_PaulaSetDat(i:uint, x:int):void {
        AUD[i].DAT = x;
    }
    [inline] final private function mt_PaulaSetLoop(i:uint, x:int, y:uint):void {
        if (x) AUD[i].REPDAT = x;
        AUD[i].REPLEN = y << 1;
    }
    [inline] final private function mt_PaulaSetPer(i:uint, x:int):void {
        if (x) AUD[i].DELTA = (3546895 / x) / f_outputFreq;
    }
    [inline] static private function mt_AmigaWord(x:uint):uint {
        return ((x << 8) | (x >> 8)) & 0xFFFF;
    }
    [inline] static private function r_u16le(arr:Vector.<uint>, off:uint):uint {
        return arr[off] + (arr[off + 1] << 8);
    }
    [inline] static private function r_u16be(arr:Vector.<uint>, off:uint):uint {
        return arr[off + 1] + (arr[off] << 8);
    }
    [inline] static private function w_u16le(arr:Vector.<uint>, off:uint, x:uint):void {
        arr[off + 0] = x & 0xFF;
        arr[off + 1] = (x >> 8) & 0xFF;
    }
    [inline] static private function w_u16be(arr:Vector.<uint>, off:uint, x:uint):void {
        x &= 0xFFFF;
        arr[off + 0] = (x >> 8) & 0xFF;
        arr[off + 1] = x & 0xFF;
    }
    [inline] static private function sign8(b:int):int {
        if(b >= 128) b -= 256
        return b;
    }

    public function PT2Player()
    {
        var i:uint;
        
        mt_ChanTemp = new Vector.<PT_CHN>(4, true);
        AUD = new Vector.<PA_CHN>(4, true);
        mt_SampleStarts = new Vector.<int>(31, true);
        blep = new Vector.<Blep>(4, true);
        blepVol = new Vector.<Blep>(4, true);
        masterBuffer = new Vector.<Number>;
        filterHi = new lossyIntegrator_t(f_outputFreq, 5.2);
        filterLo = new lossyIntegrator_t(f_outputFreq, 5000);
        
        for (i = 0; i < 4; i++) 
        {
            mt_ChanTemp[i] = new PT_CHN();
            mt_ChanTemp[i].n_index = i;
            AUD[i] = new PA_CHN();
            blep[i] = new Blep();
            blepVol[i] = new Blep();
        }
        
        mt_TimerVal     = (f_outputFreq * 125) / 50;
        samplesPerFrame = mt_TimerVal / 125;
        mt_genPans(C.INITIAL_STEREO_SEP_PERCENTAGE);
        
        audioOut = new Sound();
        audioOut.addEventListener(SampleDataEvent.SAMPLE_DATA, audioLoop);
        sc = audioOut.play();
    }
    
    /* CODE START */
    
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

                if (ch.n_wavestart != C.NULL) /* added for safety reasons */
                {
                    if (++ch.n_wavestart >= (ch.n_loopstart + ch.n_replen))
                        ch.n_wavestart = ch.n_loopstart;

                    //TODO: well, shit.
                    /*
                    var kuk:int = D[ch.n_wavestart];
                    kuk = kuk >= 128 ? kuk - 256 : kuk;
                    kuk = -1 - kuk;
                    kuk = kuk < 0 ? kuk + 256 : kuk;
                    kuk &= 0xFF;
                    D[ch.n_wavestart] = kuk;
                    */
                    D[ch.n_wavestart] = ( -1 - D[ch.n_wavestart]) & 0xFF;
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
    
    private function mt_DoRetrig(ch:PT_CHN):void
    {
        mt_PaulaSetDat(ch.n_index, ch.n_start); // n_start is increased on 9xx
        mt_PaulaSetLen(ch.n_index, ch.n_length);
        mt_PaulaSetPer(ch.n_index, ch.n_period);
        mt_PaulaStart(ch.n_index); // this resets resampling pos
        mt_PaulaSetLoop(ch.n_index, ch.n_loopstart, ch.n_replen);
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
                mt_DoRetrig(ch);
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
            if (ch.n_note & 0x0FFF)
                mt_DoRetrig(ch);
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

        vibratoTemp = (ch.n_vibratopos >> 2) & 0x1F; /* should be unsigned now (if not, then cast) */
        vibratoData =  ch.n_wavecontrol      & 0x03;

        if (!vibratoData)
        {
            vibratoData = C.mt_VibratoTable[vibratoTemp];
        }
        else
        {
            if (vibratoData == 1)
            {
                if (ch.n_vibratopos > 127)
                    vibratoData = 255 - (vibratoTemp << 3);
                else
                    vibratoData = vibratoTemp << 3;
            }
            else
            {
                vibratoData = 255;
            }
        }

        vibratoData = (vibratoData * (ch.n_vibratocmd & 0x0F)) / 128;

        if (ch.n_vibratopos > 127)
            vibratoData = ch.n_period - vibratoData;
        else
            vibratoData = ch.n_period + vibratoData;

        mt_PaulaSetPer(ch.n_index, vibratoData);

        ch.n_vibratopos += ((ch.n_vibratocmd >> 2) & 0x3C);
        ch.n_vibratopos &= 0xFF;
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

        tremoloTemp = (ch.n_tremolopos  >> 2) & 0x1F; /* should be unsigned now (if not, then cast) */
        tremoloData = (ch.n_wavecontrol >> 4) & 0x03;

        if (!tremoloData)
        {
            tremoloData = C.mt_VibratoTable[tremoloTemp];
        }
        else
        {
            if (tremoloData == 1)
            {
                if (ch.n_vibratopos > 127) /* PT bug, but don't fix this one */
                    tremoloData = 255 - (tremoloTemp << 3);
                else
                    tremoloData = tremoloTemp << 3;
            }
            else
            {
                tremoloData = 255;
            }
        }

        tremoloData = (tremoloData * (ch.n_tremolocmd & 0x0F)) / 64;

        if (ch.n_tremolopos > 127)
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
        ch.n_tremolopos &= 0xFF;
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
            ch.n_length = 1; // this must NOT be set to 0! 1 is the correct value.
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
            case 0x08: /*mt_KarplusStrong(ch);*/ break;
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
        switch ((ch.n_cmd & 0x0F00) >> 8)
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
            switch ((ch.n_cmd & 0x0F00) >> 8)
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
        if (i < 36)
            ch.n_period = mt_PeriodTable[(36 * ch.n_finetune) + i];

        if ((ch.n_cmd & 0x0FF0) != 0x0ED0) /* no note delay */
        {
            if (!(ch.n_wavecontrol & 0x04)) ch.n_vibratopos = 0;
            if (!(ch.n_wavecontrol & 0x40)) ch.n_tremolopos = 0;

            mt_PaulaSetLen(ch.n_index, ch.n_length);
            mt_PaulaSetDat(ch.n_index, ch.n_start);
            
            if (ch.n_length == 0)
            {
                ch.n_loopstart = 0;
                ch.n_replen = 1;
            }
            
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
        if (!ch.n_note && !ch.n_cmd)
            mt_PaulaSetPer(ch.n_index, ch.n_period);

        pattData = new Vector.<uint>(4, true);
        pattData[0] = D[mt_PattPosOff + 0];
        pattData[1] = D[mt_PattPosOff + 1];
        pattData[2] = D[mt_PattPosOff + 2];
        pattData[3] = D[mt_PattPosOff + 3];

        ch.n_note  = (pattData[0] << 8) | pattData[1];
        ch.n_cmd   = (pattData[2] << 8) | pattData[3];

        sample = (pattData[0] & 0xF0) | (pattData[2] >> 4);
        if ((sample >= 1) && (sample <= 31)) /* BUGFIX: don't do samples >31 */
        {
            sample--;
            sampleOffset = 42 + (30 * sample);

            ch.n_start    = mt_SampleStarts[sample];
            ch.n_finetune = D[sampleOffset + 2];
            ch.n_volume   = D[sampleOffset + 3];
            ch.n_length   = r_u16be(D, sampleOffset + 0);
            ch.n_replen   = r_u16be(D, sampleOffset + 6);
            
            mt_PaulaSetVol(ch.n_index, ch.n_volume);
            
            repeat = r_u16be(D, sampleOffset + 4);
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
                cmd = (ch.n_cmd & 0x0F00) >> 8;
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
        
        mt_PattPosOff += 4;
    }

    private function mt_NextPosition():void
    {
        mt_PatternPos  = mt_PBreakPos << 4
        mt_PBreakPos   = 0;
        mt_PosJumpFlag = 0;

        mt_SongPos = (mt_SongPos + 1) & 0x7F;
        if (mt_SongPos >= D[950])
            mt_SongPos = 0;

        mt_PattOff = 1084 + (D[952 + mt_SongPos] << 10);
    }

    private function mt_MusicIRQ():void
    {
        var i:uint;
        
        mt_Counter++;
        if (mt_Counter >= mt_Speed)
        {
            mt_Counter = 0;

            if (!mt_PattDelTime2)
            {
                mt_PattPosOff = mt_PattOff + mt_PatternPos;
                
                for (i = 0; i < 4; i++) 
                {
                    mt_PlayVoice(mt_ChanTemp[i]);
                    mt_PaulaSetLoop(i, mt_ChanTemp[i].n_loopstart, mt_ChanTemp[i].n_replen);
                }
            }
            else
            {
                for (i = 0; i < 4; i++) 
                {
                    mt_CheckEfx(mt_ChanTemp[i]);
                }
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
            for (i = 0; i < 4; i++) 
            {
                mt_CheckEfx(mt_ChanTemp[i]);
            }
            
            if (mt_PosJumpFlag) mt_NextPosition();
        }
    }
    
    public function mt_Init(mt_Data:ByteArray):void
    {
        var sampleStarts:uint;                  //*uint8_t
        var pattNum:int;
        var i:uint;
        var p:uint, p0:uint, p2:uint, p3:uint;  //*uint16_t
        var j:uint;
        var lastPeriod:uint;
        
        //it be faster an shiet
        D = new Vector.<uint>(mt_Data.length);
        for (i = 0; i < mt_Data.length ; i++) 
        {
            D[i] = mt_Data[i];
        }
        

        pattNum = 0;
        for (i = 0; i < 128; ++i)
        {
            if (D[952 + i] > pattNum)
                pattNum = D[952 + i];
        }
        pattNum++;
        sampleStarts = 1084 + (pattNum << 10);
        for (i = 0; i < 31; ++i)
        {
            mt_SampleStarts[i] = sampleStarts;
            p = 42 + (30 * i);//uint16_t *
            p0 = r_u16be(D, p + 0);
            p2 = r_u16be(D, p + 4);
            p3 = r_u16be(D, p + 6);
            
            
            // loop point sanity checking
            if ((p2 + p3) > p0)
            {
                if (((p2 / 2) + p3) <= p0)
                {
                    // fix for poorly converted STK->PT modules
                    p2 /= 2;
                }
                else
                {
                    // loop points are still illegal, deactivate loop
                    p2 = 0;
                    p3 = 1;
                }
            }
            
            if (p3 <= 1)
            {
                p3 = 1; // Fix illegal loop repeats (f.ex. from FT2 .MODs)

                // If no loop, zero first two samples of data to prevent "beep"
                D[sampleStarts + 0] = 0;
                D[sampleStarts + 1] = 0;
            }
            
            w_u16be(D, p + 0, p0);
            w_u16be(D, p + 4, p2);
            w_u16be(D, p + 6, p3);
            
            sampleStarts += p0 << 1;
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
        mt_PattOff      = 1084 + (D[952] << 10);
    }

    private function sinApx(x:Number):Number
    {
        x = x * (2.0 - x);
        return (x * 1.09742972 + x * x * 0.31678383);
    }
    private function cosApx(x:Number):Number
    {
        x = (1.0 - x) * (1.0 + x);
        return (x * 1.09742972 + x * x * 0.31678383);
    }

    private function mt_genPans(stereoSeparation:uint):void
    {
        var scaledPanPos:uint;

        var p:Number;

        scaledPanPos = (stereoSeparation * 128) / 100;

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
    
    private function mixSampleBlock_BLEP(streamOut:ByteArray, numSamples:uint):void
    {
        var NULL:uint = C.NULL;
        
        var i:uint;
        var sndOut:ByteArray;
        var j:uint;

        var tempSample:Number;
        var tempVolume:Number;
        var L:Number;
        var R:Number;

        var v:PA_CHN;
        var bSmp:Blep;
        var bVol:Blep;

        masterBuffer.length = numSamples * 2;
        for (i = 0; i < masterBuffer.length; i++) masterBuffer[i] = 0.0;

        for (i = 0; i < 4; ++i)
        {
            v = AUD[i];
            bSmp = blep[i];
            bVol = blepVol[i];

            if (v.TRIGGER && v.DAT != NULL)
            {
                for (j = 0; j < numSamples; ++j)
                {
                    if (v.DAT == NULL)
                    {
                    tempSample = 0.0
                    }else
                    {
                        var kuk:int = D[v.DAT + v.POS];
                        kuk = kuk >= 128 ? kuk - 256 : kuk;
                        tempSample = kuk * (1.0 / 128.0);
                    }
                    tempVolume = v.VOL;

                    if (tempSample != bSmp.lastValue)
                    {
                        if ((v.LASTDELTA > 0.0) && (v.LASTDELTA > v.LASTFRAC))
                            bSmp.blepAdd(v.LASTFRAC / v.LASTDELTA, bSmp.lastValue - tempSample);

                        bSmp.lastValue = tempSample;
                    }

                    if (tempVolume != bVol.lastValue)
                    {
                        bVol.blepAdd(0.0, bVol.lastValue - tempVolume);
                        bVol.lastValue = tempVolume;
                    }

                    if (bSmp.samplesLeft) tempSample += bSmp.blepRun();
                    if (bVol.samplesLeft) tempVolume += bVol.blepRun();

                    tempSample *= tempVolume;
                    masterBuffer[j*2+0] += (tempSample * v.PANL);
                    masterBuffer[j*2+1] += (tempSample * v.PANR);

                    v.FRAC += v.DELTA;
                    if (v.FRAC >= 1.0)
                    {
                        v.POS++;
                        v.FRAC -= 1.0;

                        v.LASTFRAC  = v.FRAC;
                        v.LASTDELTA = v.DELTA;

                        if (v.POS >= v.LEN)
                        {
                            v.DAT  = v.REPDAT;
                            v.POS -= v.LEN;
                            v.LEN  = v.REPLEN;
                        }
                    }
                }
            }
        }

        if (amigaFilter)
        {
            filterHi.lossyIntegratorHighPass(masterBuffer, masterBuffer);
            filterLo.lossyIntegrator(masterBuffer, masterBuffer);
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
                L = masterBuffer[j*2+0] * (-32767.0 / 3.0);
                R = masterBuffer[j*2+1] * (-32767.0 / 3.0);

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

        
        
        mt_TempoMode = tempoMode ? 1 : 0; /* 0 = cia, 1 = vblank */
        mt_Enable    = 1;
    }

    public function pt2play_SetStereoSep(percentage:uint):void
    {
        if (percentage > 100) percentage = 100;
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
                mixSampleBlock_BLEP(event.data, samplesTodo);
                
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