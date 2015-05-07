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
**
** You need to link winmm.lib for this to compile (-lwinmm)
**
** User functions:
**
** #include <stdint.h>
**
** enum
** {
**     CIA_TEMPO_MODE    = 0,
**     VBLANK_TEMPO_MODE = 1
** };
**
** int8_t pt2play_Init(uint32_t outputFreq);
** void pt2play_Close(void);
** void pt2play_PauseSong(int8_t pause);
** void pt2play_PlaySong(uint8_t *moduleData, int8_t tempoMode);
** void pt2play_SetStereoSep(uint8_t percentage);
*/

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#define _USE_MATH_DEFINES

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h> // tanf()
#include <windows.h>
#include <mmsystem.h>

#ifdef _MSC_VER
#pragma warning(disable:4127) // disable while (1) warnings
#define inline __forceinline
#endif

#define SOUND_BUFFERS 7
#define INITIAL_STEREO_SEP_PERCENTAGE 20 /* stereo separation in percent */


/* BLEP CONSTANTS */
#define ZC 8
#define OS 5
#define SP 5
#define NS (ZC * OS / SP)
#define RNS 7 // RNS = (2^ > NS) - 1


/* STRUCTS */
typedef struct blep_data
{
    int32_t index;
    int32_t samplesLeft;
    float buffer[RNS + 1];
    float lastValue;
} BLEP;

typedef struct lossyIntegrator_t
{
    float buffer[2];
    float coefficient[2];

} lossyIntegrator_t;

typedef struct
{
    int8_t *n_start;
    int8_t *n_wavestart;
    int8_t *n_loopstart;
    int8_t n_index;
    int8_t n_volume;
    int8_t n_toneportdirec;
    int8_t n_vibratopos;
    int8_t n_tremolopos;
    int8_t n_pattpos;
    int8_t n_loopcount;
    uint8_t n_wavecontrol;
    uint8_t n_glissfunk;
    uint8_t n_sampleoffset;
    uint8_t n_toneportspeed;
    uint8_t n_vibratocmd;
    uint8_t n_tremolocmd;
    uint8_t n_finetune;
    uint8_t n_funkoffset;
    int16_t n_period;
    int16_t n_note;
    int16_t n_wantedperiod;
    uint16_t n_cmd;
    uint32_t n_length;
    uint32_t n_replen;
    uint32_t n_repend;
} PT_CHN;

typedef struct
{
    int8_t *DAT;
    int8_t *REPDAT;
    int8_t TRIGGER;

    uint32_t REPLEN;
    uint32_t POS;
    uint32_t LEN;

    float LASTDELTA;
    float DELTA;
    float LASTFRAC;
    float FRAC;
    float VOL;
    float PANL;
    float PANR;
} PA_CHN;


/* VARIABLES */
static PT_CHN mt_ChanTemp[4];

static PA_CHN AUD[4];

static int8_t *mt_SampleStarts[31];

static lossyIntegrator_t filterHi;

static int32_t soundBufferSize;
static int8_t mt_TempoMode;
static int8_t mt_SongPos;
static int8_t mt_PosJumpFlag;
static int8_t mt_PBreakFlag;
static int8_t mt_Enable;
static int8_t mt_PBreakPos;
static int8_t mt_PattDelTime;
static int8_t mt_PattDelTime2;
static uint8_t *mt_SongDataPtr;
static uint8_t mt_LowMask;
static uint8_t mt_Counter;
static uint8_t mt_Speed;
static int16_t *mt_PeriodTable;
static uint16_t mt_PatternPos;
static int32_t mt_TimerVal;
static uint32_t mt_PattPosOff;
static uint32_t mt_PattOff;
static float f_outputFreq;
static WAVEHDR waveBlocks[SOUND_BUFFERS];
static HWAVEOUT hWaveOut;
static WAVEFORMATEX wfx;
static BLEP blep[4];
static BLEP blepVol[4];

/* pre-initialized variables */
static float *masterBufferL              = NULL;
static float *masterBufferR              = NULL;
static int8_t *mixerBuffer               = NULL;
static int32_t samplesLeft               = 0; /* must be signed */
static volatile int8_t mixingMutex       = 0;
static volatile int8_t isMixing          = 0;
static volatile uint32_t samplesPerFrame = 882;


/* MACROS */
#define mt_PaulaStop(i) AUD[i].POS=0;AUD[i].FRAC=0.0f;AUD[i].TRIGGER=0;
#define mt_PaulaStart(i) AUD[i].POS=0;AUD[i].FRAC=0.0f;AUD[i].TRIGGER=1;
#define mt_PaulaSetVol(i, x) AUD[i].VOL=(float)(x)*(1.0f/64.0f);
#define mt_PaulaSetLen(i, x) AUD[i].LEN=x<<1;
#define mt_PaulaSetDat(i, x) AUD[i].DAT=x;
#define mt_PaulaSetLoop(i, x, y) if(x){AUD[i].REPDAT=x;}AUD[i].REPLEN=y<<1;
#define mt_PaulaSetPer(i, x) if(x){AUD[i].DELTA=(float)(3546895/(x))/f_outputFreq;}
#define mt_AmigaWord(x) ((uint16_t)(((x)<<8)|((x)>>8)))


/* TABLES */
static const uint8_t mt_FunkTable[16] =
{
    0x00, 0x05, 0x06, 0x07, 0x08, 0x0A, 0x0B, 0x0D,
    0x10, 0x13, 0x16, 0x1A, 0x20, 0x2B, 0x40, 0x80
};

static const uint8_t mt_VibratoTable[32] =
{
    0x00, 0x18, 0x31, 0x4A, 0x61, 0x78, 0x8D, 0xA1,
    0xB4, 0xC5, 0xD4, 0xE0, 0xEB, 0xF4, 0xFA, 0xFD,
    0xFF, 0xFD, 0xFA, 0xF4, 0xEB, 0xE0, 0xD4, 0xC5,
    0xB4, 0xA1, 0x8D, 0x78, 0x61, 0x4A, 0x31, 0x18
};

static const int8_t mt_PeriodDiffs[576] =
{
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
};

static const uint32_t blepData[48] =
{
    0x3F7FE1F1, 0x3F7FD548, 0x3F7FD6A3, 0x3F7FD4E3,
    0x3F7FAD85, 0x3F7F2152, 0x3F7DBFAE, 0x3F7ACCDF,
    0x3F752F1E, 0x3F6B7384, 0x3F5BFBCB, 0x3F455CF2,
    0x3F26E524, 0x3F0128C4, 0x3EACC7DC, 0x3E29E86B,
    0x3C1C1D29, 0xBDE4BBE6, 0xBE3AAE04, 0xBE48DEDD,
    0xBE22AD7E, 0xBDB2309A, 0xBB82B620, 0x3D881411,
    0x3DDADBF3, 0x3DE2C81D, 0x3DAAA01F, 0x3D1E769A,
    0xBBC116D7, 0xBD1402E8, 0xBD38A069, 0xBD0C53BB,
    0xBC3FFB8C, 0x3C465FD2, 0x3CEA5764, 0x3D0A51D6,
    0x3CEAE2D5, 0x3C92AC5A, 0x3BE4CBF7, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000
};


/* CODE START */
static void calcCoeffLossyIntegrator(float sr, float hz, lossyIntegrator_t *filter)
{
    filter->coefficient[0] = tanf((float)(M_PI) * hz / sr);
    filter->coefficient[1] = 1.0f / (1.0f + filter->coefficient[0]);
}

static void clearLossyIntegrator(lossyIntegrator_t *filter)
{
    filter->buffer[0] = 0.0f;
    filter->buffer[1] = 0.0f;
}

static inline void lossyIntegrator(lossyIntegrator_t *filter, float *in, float *out)
{
    float output;

    // left channel
    output            = (filter->coefficient[0] * in[0] + filter->buffer[0]) * filter->coefficient[1];
    filter->buffer[0] = filter->coefficient[0] * (in[0] - output) + output + 1e-10f;
    out[0]            = output;

    // right channel
    output            = (filter->coefficient[0] * in[1] + filter->buffer[1]) * filter->coefficient[1];
    filter->buffer[1] = filter->coefficient[0] * (in[1] - output) + output + 1e-10f;
    out[1]            = output;
}

static inline void lossyIntegratorHighPass(lossyIntegrator_t *filter, float *in, float *out)
{
    float low[2];

    lossyIntegrator(filter, in, low);

    out[0] = in[0] - low[0];
    out[1] = in[1] - low[1];
}

static void blepAdd(BLEP *b, float offset, float amplitude)
{
    int8_t n;
    uint32_t i;

    const float *src;
    float f;

    n   = NS;
    i   = (uint32_t)(offset * SP);
    src = (const float *)(blepData) + i + OS;
    f   = (offset * SP) - i;
    i   = b->index;

    while (n--)
    {
        b->buffer[i] += (amplitude * (src[0] + (src[1] - src[0]) * f));
        src          += SP;

        i++;
        i &= RNS;
    }

    b->samplesLeft = NS;
}

static float blepRun(BLEP *b)
{
    float output;

    output              = b->buffer[b->index];
    b->buffer[b->index] = 0.0f;

    b->index++;
    b->index &= RNS;

    b->samplesLeft--;

    return (output);
}

static void mt_UpdateFunk(PT_CHN *ch)
{
    int8_t funkspeed;
    
    funkspeed = ch->n_glissfunk >> 4;
    if (funkspeed > 0)
    {
        ch->n_funkoffset += mt_FunkTable[funkspeed];
        if (ch->n_funkoffset & 128)
        {
            ch->n_funkoffset = 0;

            if (ch->n_wavestart != NULL) /* added for safety reasons */
            {
                if (++ch->n_wavestart >= (ch->n_loopstart + ch->n_replen))
                    ch->n_wavestart = ch->n_loopstart;

                *ch->n_wavestart = -1 - *ch->n_wavestart;
            }
        }
    }
}

static void mt_SetGlissControl(PT_CHN *ch)
{
    ch->n_glissfunk = (ch->n_glissfunk & 0xF0) | (ch->n_cmd & 0x000F);
}

static void mt_SetVibratoControl(PT_CHN *ch)
{
    ch->n_wavecontrol = (ch->n_wavecontrol & 0xF0) | (ch->n_cmd & 0x000F);
}

static void mt_SetFineTune(PT_CHN *ch)
{
    ch->n_finetune = ch->n_cmd & 0x000F;
}

static void mt_JumpLoop(PT_CHN *ch)
{
    if (!mt_Counter)
    {
        if (!(ch->n_cmd & 0x000F))
        {
            ch->n_pattpos = (int8_t)(mt_PatternPos >> 4);
        }
        else
        {
            if (!ch->n_loopcount)
            {
                ch->n_loopcount = ch->n_cmd & 0x000F;
            }
            else
            {
                if (!--ch->n_loopcount) return;
            }

            mt_PBreakPos  = ch->n_pattpos;
            mt_PBreakFlag = 1;
        }
    }
}

static void mt_SetTremoloControl(PT_CHN *ch)
{
    ch->n_wavecontrol = ((ch->n_cmd & 0x000F) << 4) | (ch->n_wavecontrol & 0x0F);
}

void mt_DoRetrig(PT_CHN *ch)
{
    mt_PaulaSetDat(ch->n_index, ch->n_start); // n_start is increased on 9xx
    mt_PaulaSetLen(ch->n_index, ch->n_length);
    mt_PaulaSetPer(ch->n_index, ch->n_period);
    mt_PaulaStart(ch->n_index); // this resets resampling pos
    mt_PaulaSetLoop(ch->n_index, ch->n_loopstart, ch->n_replen);
}

static void mt_RetrigNote(PT_CHN *ch)
{
    if (ch->n_cmd & 0x000F)
    {
        if (!mt_Counter)
        {
            if (ch->n_note & 0x0FFF) return;
        }

        if (!(mt_Counter % (ch->n_cmd & 0x000F)))
            mt_DoRetrig(ch);
    }
}

static void mt_VolumeSlide(PT_CHN *ch)
{
    if (!((ch->n_cmd & 0x00FF) >> 4))
    {
        ch->n_volume -= (ch->n_cmd & 0x000F);
        if (ch->n_volume < 0) ch->n_volume = 0;
    }
    else
    {
        ch->n_volume += ((ch->n_cmd & 0x00FF) >> 4);
        if (ch->n_volume > 64) ch->n_volume = 64;
    }

    mt_PaulaSetVol(ch->n_index, ch->n_volume);
}

static void mt_VolumeFineUp(PT_CHN *ch)
{
    if (!mt_Counter)
    {
        ch->n_volume += (ch->n_cmd & 0x000F);
        if (ch->n_volume > 64) ch->n_volume = 64;

        mt_PaulaSetVol(ch->n_index, ch->n_volume);
    }
}

static void mt_VolumeFineDown(PT_CHN *ch)
{
    if (!mt_Counter)
    {
        ch->n_volume -= (ch->n_cmd & 0x000F);
        if (ch->n_volume < 0) ch->n_volume = 0;

        mt_PaulaSetVol(ch->n_index, ch->n_volume);
    }
}

static void mt_NoteCut(PT_CHN *ch)
{
    if (mt_Counter == (ch->n_cmd & 0x000F))
    {
        ch->n_volume = 0;
        mt_PaulaSetVol(ch->n_index, 0);
    }
}

static void mt_NoteDelay(PT_CHN *ch)
{
    if (mt_Counter == (ch->n_cmd & 0x000F))
    {
        if (ch->n_note & 0x0FFF)
            mt_DoRetrig(ch);
    }
}

static void mt_PatternDelay(PT_CHN *ch)
{
    if (!mt_Counter)
    {
        if (!mt_PattDelTime2)
            mt_PattDelTime = (ch->n_cmd & 0x000F) + 1;
    }
}

static void mt_FunkIt(PT_CHN *ch)
{
    if (!mt_Counter)
    {
        ch->n_glissfunk = ((ch->n_cmd & 0x000F) << 4) | (ch->n_glissfunk & 0x0F);

        if (ch->n_glissfunk & 0xF0)
            mt_UpdateFunk(ch);
    }
}

static void mt_PositionJump(PT_CHN *ch)
{
    mt_SongPos     = (ch->n_cmd & 0x00FF) - 1; /* 0xFF (B00) jumps to pat 0 */
    mt_PBreakPos   = 0;
    mt_PosJumpFlag = 1;
}

static void mt_VolumeChange(PT_CHN *ch)
{
    ch->n_volume = ch->n_cmd & 0x00FF;
    if (ch->n_volume > 64) ch->n_volume = 64;

    mt_PaulaSetVol(ch->n_index, ch->n_volume);
}

static void mt_PatternBreak(PT_CHN *ch)
{
    mt_PBreakPos = (((ch->n_cmd & 0x00FF) >> 4) * 10) + (ch->n_cmd & 0x000F);
    if (mt_PBreakPos > 63)
        mt_PBreakPos = 0;

    mt_PosJumpFlag = 1;
}

static void mt_SetSpeed(PT_CHN *ch)
{
    if (ch->n_cmd & 0x00FF)
    {
        mt_Counter = 0;

        if (mt_TempoMode || ((ch->n_cmd & 0x00FF) < 32))
            mt_Speed = ch->n_cmd & 0x00FF;
        else
            samplesPerFrame = (int16_t)(mt_TimerVal / (ch->n_cmd & 0x00FF));
    }
}

static void mt_Arpeggio(PT_CHN *ch)
{
    uint8_t i;
    uint8_t dat;
    const int16_t *arpPointer;

    dat = mt_Counter % 3;
    if (!dat)
    {
        mt_PaulaSetPer(ch->n_index, ch->n_period);
    }
    else
    {
        if (dat == 1)
            dat = (ch->n_cmd & 0x00FF) >> 4;
        else if (dat == 2)
            dat = ch->n_cmd & 0x000F;

        arpPointer = &mt_PeriodTable[36 * ch->n_finetune];
        for (i = 0; i < 36; ++i)
        {
            if (ch->n_period >= arpPointer[i])
            {
                mt_PaulaSetPer(ch->n_index, arpPointer[i + dat]);
                break;
            }
        }
    }
}

static void mt_PortaUp(PT_CHN *ch)
{
    ch->n_period -= ((ch->n_cmd & 0x00FF) & mt_LowMask);
    mt_LowMask = 0xFF;

    if ((ch->n_period & 0x0FFF) < 113)
    {
        ch->n_period &= 0xF000;
        ch->n_period |= 113;
    }

    mt_PaulaSetPer(ch->n_index, ch->n_period & 0x0FFF);
}

static void mt_PortaDown(PT_CHN *ch)
{
    ch->n_period += ((ch->n_cmd & 0x00FF) & mt_LowMask);
    mt_LowMask = 0xFF;

    if ((ch->n_period & 0x0FFF) > 856)
    {
        ch->n_period &= 0xF000;
        ch->n_period |= 856;
    }

    mt_PaulaSetPer(ch->n_index, ch->n_period & 0x0FFF);
}

static void mt_FinePortaUp(PT_CHN *ch)
{
    if (!mt_Counter)
    {
        mt_LowMask = 0x0F;
        mt_PortaUp(ch);
    }
}

static void mt_FinePortaDown(PT_CHN *ch)
{
    if (!mt_Counter)
    {
        mt_LowMask = 0x0F;
        mt_PortaDown(ch);
    }
}

static void mt_SetTonePorta(PT_CHN *ch)
{
    uint8_t i;
    const int16_t *portaPointer;
    uint16_t note;

    note         = ch->n_note & 0x0FFF;
    portaPointer = &mt_PeriodTable[36 * ch->n_finetune];

    i = 0;
    while (1)
    {
        if (note >= portaPointer[i])
            break;

        if (++i >= 36)
        {
            i = 35;
            break;
        }
    }

    if ((ch->n_finetune & 8) && i) i--;

    ch->n_wantedperiod  = portaPointer[i];
    ch->n_toneportdirec = 0;

    if (ch->n_period == ch->n_wantedperiod)
        ch->n_wantedperiod = 0;
    else if (ch->n_period > ch->n_wantedperiod)
        ch->n_toneportdirec = 1;
}

static void mt_TonePortNoChange(PT_CHN *ch)
{
    uint8_t i;
    const int16_t *portaPointer;

    if (ch->n_wantedperiod)
    {
        if (ch->n_toneportdirec)
        {
            ch->n_period -= ch->n_toneportspeed;
            if (ch->n_period <= ch->n_wantedperiod)
            {
                ch->n_period       = ch->n_wantedperiod;
                ch->n_wantedperiod = 0;
            }
        }
        else
        {
            ch->n_period += ch->n_toneportspeed;
            if (ch->n_period >= ch->n_wantedperiod)
            {
                ch->n_period       = ch->n_wantedperiod;
                ch->n_wantedperiod = 0;
            }
        }

        if (!(ch->n_glissfunk & 0x0F))
        {
            mt_PaulaSetPer(ch->n_index, ch->n_period);
        }
        else
        {
            portaPointer = &mt_PeriodTable[36 * ch->n_finetune];

            i = 0;
            while (1)
            {
                if (ch->n_period >= portaPointer[i])
                    break;

                if (++i >= 36)
                {
                    i = 35;
                    break;
                }
            }

            mt_PaulaSetPer(ch->n_index, portaPointer[i]);
        }
    }
}

static void mt_TonePortamento(PT_CHN *ch)
{
    if (ch->n_cmd & 0x00FF)
    {
        ch->n_toneportspeed = ch->n_cmd & 0x00FF;
        ch->n_cmd &= 0xFF00;
    }

    mt_TonePortNoChange(ch);
}

static void mt_VibratoNoChange(PT_CHN *ch)
{
    uint8_t vibratoTemp;
    int16_t vibratoData;

    vibratoTemp = (ch->n_vibratopos >> 2) & 0x1F;
    vibratoData =  ch->n_wavecontrol      & 0x03;

    if (!vibratoData)
    {
        vibratoData = mt_VibratoTable[vibratoTemp];
    }
    else
    {
        if (vibratoData == 1)
        {
            if (ch->n_vibratopos < 0)
                vibratoData = 255 - (vibratoTemp << 3);
            else
                vibratoData = vibratoTemp << 3;
        }
        else
        {
            vibratoData = 255;
        }
    }

    vibratoData = (vibratoData * (ch->n_vibratocmd & 0x0F)) >> 7;

    if (ch->n_vibratopos < 0)
        vibratoData = ch->n_period - vibratoData;
    else
        vibratoData = ch->n_period + vibratoData;

    mt_PaulaSetPer(ch->n_index, vibratoData);

    ch->n_vibratopos += ((ch->n_vibratocmd >> 2) & 0x3C);
}

static void mt_Vibrato(PT_CHN *ch)
{
    if (ch->n_cmd & 0x00FF)
    {
        if (ch->n_cmd & 0x000F)
            ch->n_vibratocmd = (ch->n_vibratocmd & 0xF0) | (ch->n_cmd & 0x000F);

        if (ch->n_cmd & 0x00F0)
            ch->n_vibratocmd = (ch->n_cmd & 0x00F0) | (ch->n_vibratocmd & 0x0F);
    }

    mt_VibratoNoChange(ch);
}

static void mt_TonePlusVolSlide(PT_CHN *ch)
{
    mt_TonePortNoChange(ch);
    mt_VolumeSlide(ch);
}

static void mt_VibratoPlusVolSlide(PT_CHN *ch)
{
    mt_VibratoNoChange(ch);
    mt_VolumeSlide(ch);
}

static void mt_Tremolo(PT_CHN *ch)
{
    int8_t tremoloTemp;
    int16_t tremoloData;

    if (ch->n_cmd & 0x00FF)
    {
        if (ch->n_cmd & 0x000F)
            ch->n_tremolocmd = (ch->n_tremolocmd & 0xF0) | (ch->n_cmd & 0x000F);

        if (ch->n_cmd & 0x00F0)
            ch->n_tremolocmd = (ch->n_cmd & 0x00F0) | (ch->n_tremolocmd & 0x0F);
    }

    tremoloTemp = (ch->n_tremolopos  >> 2) & 0x1F;
    tremoloData = (ch->n_wavecontrol >> 4) & 0x03;

    if (!tremoloData)
    {
        tremoloData = mt_VibratoTable[tremoloTemp];
    }
    else
    {
        if (tremoloData == 1)
        {
            if (ch->n_vibratopos < 0) /* PT bug, but don't fix this one */
                tremoloData = 255 - (tremoloTemp << 3);
            else
                tremoloData = tremoloTemp << 3;
        }
        else
        {
            tremoloData = 255;
        }
    }

    tremoloData = (tremoloData * (ch->n_tremolocmd & 0x0F)) >> 6;

    if (ch->n_tremolopos < 0)
    {
        tremoloData = ch->n_volume - tremoloData;
        if (tremoloData < 0) tremoloData = 0;
    }
    else
    {
        tremoloData = ch->n_volume + tremoloData;
        if (tremoloData > 64) tremoloData = 64;
    }

    mt_PaulaSetVol(ch->n_index, tremoloData);

    ch->n_tremolopos += ((ch->n_tremolocmd >> 2) & 0x3C);
}

static void mt_SampleOffset(PT_CHN *ch)
{
    uint16_t newOffset;

    if (ch->n_cmd & 0x00FF)
        ch->n_sampleoffset = ch->n_cmd & 0x00FF;

    newOffset = ch->n_sampleoffset << 7;
    if (newOffset < ch->n_length)
    {
        ch->n_length -= newOffset;
        ch->n_start += (newOffset << 1);
    }
    else
    {
        ch->n_length = 1; // this must NOT be set to 0! 1 is the correct value.
    }
}

static void mt_E_Commands(PT_CHN *ch)
{
    switch ((ch->n_cmd & 0x00F0) >> 4)
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

static void mt_CheckMoreEfx(PT_CHN *ch)
{
    switch ((ch->n_cmd & 0x0F00) >> 8)
    {
        case 0x09: mt_SampleOffset(ch); break;
        case 0x0B: mt_PositionJump(ch); break;
        case 0x0D: mt_PatternBreak(ch); break;
        case 0x0E: mt_E_Commands(ch);   break;
        case 0x0F: mt_SetSpeed(ch);     break;
        case 0x0C: mt_VolumeChange(ch); break;

        default: mt_PaulaSetPer(ch->n_index, ch->n_period); break;
    }
}

static void mt_CheckEfx(PT_CHN *ch)
{
    mt_UpdateFunk(ch);

    if (ch->n_cmd & 0x0FFF)
    {
        switch ((ch->n_cmd & 0x0F00) >> 8)
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
                mt_PaulaSetPer(ch->n_index, ch->n_period);
                mt_Tremolo(ch);
            break;
            case 0x0A:
                mt_PaulaSetPer(ch->n_index, ch->n_period);
                mt_VolumeSlide(ch);
            break;

            default: mt_PaulaSetPer(ch->n_index, ch->n_period); break;
        }
    }
    else
    {
        mt_PaulaSetPer(ch->n_index, ch->n_period);
    }
}

static void mt_SetPeriod(PT_CHN *ch)
{
    uint8_t i;
    uint16_t note;

    note = ch->n_note & 0x0FFF;
    for (i = 0; i < 36; ++i)
    {
        if (note >= mt_PeriodTable[i]) break;
    }

    if (i < 36)
        ch->n_period = mt_PeriodTable[(36 * ch->n_finetune) + i];

    if ((ch->n_cmd & 0x0FF0) != 0x0ED0) /* no note delay */
    {
        if (!(ch->n_wavecontrol & 0x04)) ch->n_vibratopos = 0;
        if (!(ch->n_wavecontrol & 0x40)) ch->n_tremolopos = 0;

        mt_PaulaSetLen(ch->n_index, ch->n_length);
        mt_PaulaSetDat(ch->n_index, ch->n_start);

        if (ch->n_length == 0)
        {
            ch->n_loopstart = 0;
            ch->n_replen = 1;
        }

        mt_PaulaSetPer(ch->n_index, ch->n_period);
        mt_PaulaStart(ch->n_index);
    }

    mt_CheckMoreEfx(ch);
}

static void mt_PlayVoice(PT_CHN *ch)
{
    uint8_t pattData[4];
    uint8_t sample;
    uint8_t cmd;
    uint16_t sampleOffset;
    uint16_t repeat;

    if (!ch->n_note && !ch->n_cmd)
        mt_PaulaSetPer(ch->n_index, ch->n_period);

    *((uint32_t *)(pattData)) = *((uint32_t *)(&mt_SongDataPtr[mt_PattPosOff]));

    ch->n_note = (pattData[0] << 8) | pattData[1];
    ch->n_cmd  = (pattData[2] << 8) | pattData[3];

    sample = (pattData[0] & 0xF0) | (pattData[2] >> 4);
    if ((sample >= 1) && (sample <= 31)) /* BUGFIX: don't do samples >31 */
    {
        sample--;
        sampleOffset = 42 + (30 * sample);

        ch->n_start    = mt_SampleStarts[sample];
        ch->n_finetune = mt_SongDataPtr[sampleOffset + 2];
        ch->n_volume   = mt_SongDataPtr[sampleOffset + 3];
        ch->n_length   = *((uint16_t *)(&mt_SongDataPtr[sampleOffset + 0]));
        ch->n_replen   = *((uint16_t *)(&mt_SongDataPtr[sampleOffset + 6]));

        mt_PaulaSetVol(ch->n_index, ch->n_volume);

        repeat = *((uint16_t *)(&mt_SongDataPtr[sampleOffset + 4]));
        if (repeat > 0)
        {
            ch->n_loopstart = ch->n_start + (repeat << 1);
            ch->n_wavestart = ch->n_loopstart;
            ch->n_length    = repeat + ch->n_replen;
        }
        else
        {
            ch->n_loopstart = ch->n_start;
            ch->n_wavestart = ch->n_start;
        }
    }

    if (ch->n_note & 0x0FFF)
    {
        if ((ch->n_cmd & 0x0FF0) == 0x0E50) /* set finetune */
        {
            mt_SetFineTune(ch);
            mt_SetPeriod(ch);
        }
        else
        {
            cmd = (ch->n_cmd & 0x0F00) >> 8;
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

static void mt_NextPosition(void)
{
    mt_PatternPos  = (uint16_t)(mt_PBreakPos) << 4;
    mt_PBreakPos   = 0;
    mt_PosJumpFlag = 0;

    mt_SongPos = (mt_SongPos + 1) & 0x7F;
    if (mt_SongPos >= mt_SongDataPtr[950])
        mt_SongPos = 0;

    mt_PattOff = 1084 + ((uint32_t)(mt_SongDataPtr[952 + mt_SongPos]) << 10);
}

static void mt_MusicIRQ(void)
{
    uint8_t i;

    mt_Counter++;
    if (mt_Counter >= mt_Speed)
    {
        mt_Counter = 0;

        if (!mt_PattDelTime2)
        {
            mt_PattPosOff = mt_PattOff + mt_PatternPos;

            for (i = 0; i < 4; ++i)
            {
                mt_PlayVoice(&mt_ChanTemp[i]);
                mt_PaulaSetLoop(i, mt_ChanTemp[i].n_loopstart, mt_ChanTemp[i].n_replen);
            }
        }
        else
        {
            for (i = 0; i < 4; ++i)
                mt_CheckEfx(&mt_ChanTemp[i]);
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
        for (i = 0; i < 4; ++i)
            mt_CheckEfx(&mt_ChanTemp[i]);

        if (mt_PosJumpFlag) mt_NextPosition();
    }
}

static void mt_Init(uint8_t *mt_Data)
{
    uint8_t *sampleStarts;
    int8_t pattNum;
    uint8_t i;
    uint16_t *p;
    uint16_t j;
    uint16_t lastPeriod;

    for (i = 0; i < 4; ++i)
        mt_ChanTemp[i].n_index = i;

    mt_SongDataPtr = mt_Data;

    pattNum = 0;
    for (i = 0; i < 128; ++i)
    {
        if (mt_SongDataPtr[952 + i] > pattNum)
            pattNum = mt_SongDataPtr[952 + i];
    }
    pattNum++;

    sampleStarts = &mt_SongDataPtr[1084 + (pattNum << 10)];
    for (i = 0; i < 31; ++i)
    {
        mt_SampleStarts[i] = (int8_t *)(sampleStarts);
        p = ((uint16_t *)(&mt_SongDataPtr[42 + (30 * i)]));

        /* swap bytes in words (Amiga word -> Intel word) */
        p[0] = mt_AmigaWord(p[0]); /* n_length */
        p[2] = mt_AmigaWord(p[2]); /* n_repeat */
        p[3] = mt_AmigaWord(p[3]); /* n_replen */

        // loop point sanity checking
        if ((p[2] + p[3]) > p[0])
        {
            if (((p[2] / 2) + p[3]) <= p[0])
            {
                // fix for poorly converted STK->PT modules
                p[2] /= 2;
            }
            else
            {
                // loop points are still illegal, deactivate loop
                p[2] = 0;
                p[3] = 1;
            }
        }

        if (p[3] <= 1)
        {
            p[3] = 1; // fix illegal loop length (f.ex. from FT2 .MODs)

            // if no loop, zero first two samples of data to prevent "beep"
            sampleStarts[0] = 0;
            sampleStarts[1] = 0;
        }

        sampleStarts += (p[0] << 1);
    }

    /*
    ** +14 for 14 extra zeroes to prevent access violation on -1
    ** (15 unsigned) finetuned samples with B-3 >+1 note arpeggios.
    ** PT was never bug free. :-)
    */
    if (mt_PeriodTable)
    {
        free(mt_PeriodTable);
        mt_PeriodTable = NULL;
    }

    mt_PeriodTable = (int16_t *)(calloc((36 * 16) + 14, sizeof (int16_t)));
    for (i = 0; i < 16; ++i)
    {
        lastPeriod = 856;
        for (j = 0; j < 36; ++j)
            lastPeriod = mt_PeriodTable[(36 * i) + j] = lastPeriod
                + mt_PeriodDiffs[(36 * i) + j];
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
    mt_PattOff      = 1084 + ((uint32_t)(mt_SongDataPtr[952]) << 10);
}

static float sinApx(float x)
{
    x = x * (2.0f - x);
    return (x * 1.09742972f + x * x * 0.31678383f);
}
static float cosApx(float x)
{
    x = (1.0f - x) * (1.0f + x);
    return (x * 1.09742972f + x * x * 0.31678383f);
}

static void mt_genPans(int8_t stereoSeparation)
{
    uint8_t scaledPanPos;

    float p;

    scaledPanPos = ((uint16_t)(stereoSeparation) * 128) / 100;

    p = (128 - scaledPanPos) * (1.0f / 256.0f);
    AUD[0].PANL = cosApx(p);
    AUD[0].PANR = sinApx(p);
    AUD[3].PANL = cosApx(p);
    AUD[3].PANR = sinApx(p);

    p = (128 + scaledPanPos) * (1.0f / 256.0f);
    AUD[1].PANL = cosApx(p);
    AUD[1].PANR = sinApx(p);
    AUD[2].PANL = cosApx(p);
    AUD[2].PANR = sinApx(p);
}

static void mixSampleBlock(int16_t *streamOut, uint32_t numSamples)
{
    uint8_t i;
    int16_t *sndOut;
    uint16_t j;

    float tempSample;
    float tempVolume;
    float out[2];

    PA_CHN *v;
    BLEP *bSmp;
    BLEP *bVol;

    memset(masterBufferL, 0, sizeof (float) * numSamples);
    memset(masterBufferR, 0, sizeof (float) * numSamples);

    for (i = 0; i < 4; ++i)
    {
        v = &AUD[i];
        bSmp = &blep[i];
        bVol = &blepVol[i];

        if (v->TRIGGER && v->DAT)
        {
            for (j = 0; j < numSamples; ++j)
            {
                tempSample = (v->DAT == NULL) ? 0.0f : ((float)(v->DAT[v->POS]) * (1.0f / 128.0f));
                tempVolume = v->VOL;

                if (tempSample != bSmp->lastValue)
                {
                    if ((v->LASTDELTA > 0.0f) && (v->LASTDELTA > v->LASTFRAC))
                        blepAdd(bSmp, v->LASTFRAC / v->LASTDELTA, bSmp->lastValue - tempSample);

                    bSmp->lastValue = tempSample;
                }

                if (tempVolume != bVol->lastValue)
                {
                    blepAdd(bVol, 0.0f, bVol->lastValue - tempVolume);
                    bVol->lastValue = tempVolume;
                }

                if (bSmp->samplesLeft) tempSample += blepRun(bSmp);
                if (bVol->samplesLeft) tempVolume += blepRun(bVol);

                tempSample *= tempVolume;
                masterBufferL[j] += (tempSample * v->PANL);
                masterBufferR[j] += (tempSample * v->PANR);

                v->FRAC += v->DELTA;
                if (v->FRAC >= 1.0f)
                {
                    v->POS++;
                    v->FRAC -= 1.0f;

                    v->LASTFRAC  = v->FRAC;
                    v->LASTDELTA = v->DELTA;

                    if (v->POS >= v->LEN)
                    {
                        v->DAT  = v->REPDAT;
                        v->POS -= v->LEN;
                        v->LEN  = v->REPLEN;
                    }
                }
            }
        }
    }

    sndOut = streamOut;
    for (j = 0; j < numSamples; ++j)
    {
        if (!mt_Enable)
        {
            *sndOut++ = 0;
            *sndOut++ = 0;
        }
        else
        {
            out[0] = masterBufferL[j];
            out[1] = masterBufferR[j];

            lossyIntegratorHighPass(&filterHi, out, out);

            out[0] *= (-32767.0f / 3.0f);
            out[1] *= (-32767.0f / 3.0f);

                 if (out[0] < -32768.0f) out[0] = -32768.0f;
            else if (out[0] >  32767.0f) out[0] =  32767.0f;
                 if (out[1] < -32768.0f) out[1] = -32768.0f;
            else if (out[1] >  32767.0f) out[1] =  32767.0f;

            *sndOut++ = (int16_t)(out[0]);
            *sndOut++ = (int16_t)(out[1]);
        }
    }
}

static void CALLBACK waveOutProc(HWAVEOUT _hWaveOut, UINT uMsg,
    DWORD_PTR dwInstance, DWORD_PTR dwParam1, DWORD_PTR dwParam2)
{
    int16_t *outputStream;
    int32_t  sampleBlock;
    int32_t  samplesTodo; /* must be signed */

    WAVEHDR *waveBlockHeader;

    /* make compiler happy! (warning C4100) */
    (void)(dwParam2);
    (void)(dwInstance);

    if (uMsg == MM_WOM_DONE)
    {
        mixingMutex = 1;

        waveBlockHeader = (WAVEHDR *)(dwParam1);
        waveOutUnprepareHeader(_hWaveOut, waveBlockHeader, sizeof (WAVEHDR));

        if (isMixing)
        {
            memcpy(waveBlockHeader->lpData, mixerBuffer, soundBufferSize);

            waveOutPrepareHeader(_hWaveOut, waveBlockHeader, sizeof (WAVEHDR));
            waveOutWrite(_hWaveOut, waveBlockHeader, sizeof (WAVEHDR));

            outputStream = (int16_t *)(mixerBuffer);
            sampleBlock  = soundBufferSize >> 2;

            while (sampleBlock)
            {
                samplesTodo = (sampleBlock < samplesLeft) ? sampleBlock : samplesLeft;
                if (samplesTodo > 0)
                {
                    mixSampleBlock(outputStream, samplesTodo);

                    outputStream  += (samplesTodo << 1);
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

        mixingMutex = 0;
    }
}

void pt2play_PauseSong(int8_t pause)
{
    mt_Enable = pause ? 0 : 1;
}

void pt2play_PlaySong(uint8_t *moduleData, int8_t tempoMode)
{
    mt_Init(moduleData);
    mt_genPans(INITIAL_STEREO_SEP_PERCENTAGE);
    clearLossyIntegrator(&filterHi);

    memset(blep,    0, sizeof (blep));
    memset(blepVol, 0, sizeof (blepVol));

    mt_TempoMode = tempoMode ? 1 : 0; /* 0 = cia, 1 = vblank */
    mt_Enable    = 1;
}

void pt2play_SetStereoSep(uint8_t percentage)
{
    if (percentage > 100)
        percentage = 100;

    mt_genPans(percentage);
}

static int8_t openMixer(uint32_t _samplingFrequency, uint32_t _soundBufferSize)
{
    uint8_t i;
    MMRESULT r;

    memset(AUD, 0, sizeof (AUD));

    if (!hWaveOut)
    {
        f_outputFreq        = (float)(_samplingFrequency);
        soundBufferSize     = _soundBufferSize;
        masterBufferL       = (float *)(malloc(soundBufferSize * sizeof (float)));
        masterBufferR       = (float *)(malloc(soundBufferSize * sizeof (float)));
        wfx.nSamplesPerSec  = _samplingFrequency;
        wfx.wBitsPerSample  = 16;
        wfx.nChannels       = 2;
        wfx.cbSize          = 0;
        wfx.wFormatTag      = WAVE_FORMAT_PCM;
        wfx.nBlockAlign     = (wfx.wBitsPerSample * wfx.nChannels) / 8;
        wfx.nAvgBytesPerSec = wfx.nBlockAlign * wfx.nSamplesPerSec;

        r = waveOutOpen(&hWaveOut, WAVE_MAPPER, &wfx, (DWORD_PTR)(waveOutProc), 0L, CALLBACK_FUNCTION);
        if (r != MMSYSERR_NOERROR) return (0);

        for (i = 0; i < SOUND_BUFFERS; ++i)
        {
            waveBlocks[i].dwBufferLength = soundBufferSize;
            waveBlocks[i].lpData         = (LPSTR)(calloc(soundBufferSize, 1));

            waveOutPrepareHeader(hWaveOut, &waveBlocks[i], sizeof (WAVEHDR));
            waveOutWrite(hWaveOut, &waveBlocks[i], sizeof (WAVEHDR));
        }

        mixerBuffer     = (int8_t *)(calloc(soundBufferSize, 1));
        isMixing        = 1;
        mt_TimerVal     = (_samplingFrequency * 125) / 50;
        samplesPerFrame = mt_TimerVal / 125;

        calcCoeffLossyIntegrator((float)(_samplingFrequency), 5.2f, &filterHi);

        return (1);
    }

    return (1);
}

int8_t pt2play_Init(uint32_t outputFreq)
{
    return (openMixer(outputFreq, 2048));
}

void pt2play_Close(void)
{
    uint8_t i;

    mt_Enable = 0;

    if (isMixing)
    {
        isMixing = 0;
        while (mixingMutex) {}

        if (hWaveOut)
        {
            for (i = 0; i < SOUND_BUFFERS; ++i)
            {
                if (waveBlocks[i].lpData)
                {
                    waveOutUnprepareHeader(hWaveOut, &waveBlocks[i], sizeof (WAVEHDR));
                    waveBlocks[i].dwFlags &= ~WHDR_PREPARED;

                    free(waveBlocks[i].lpData);
                    waveBlocks[i].lpData = NULL;
                }
            }

            waveOutReset(hWaveOut);
            waveOutClose(hWaveOut);

            hWaveOut = 0;

            if (mixerBuffer)    free(mixerBuffer);    mixerBuffer    = NULL;
            if (masterBufferL)  free(masterBufferL);  masterBufferL  = NULL;
            if (masterBufferR)  free(masterBufferR);  masterBufferR  = NULL;
            if (mt_PeriodTable) free(mt_PeriodTable); mt_PeriodTable = NULL;
        }
    }
}

/* EOF */