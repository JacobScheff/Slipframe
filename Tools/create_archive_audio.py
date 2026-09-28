"""Original deterministic synthesis for the archive clue motif and Gyre Gate.

Requires NumPy and ffmpeg; Blender's bundled Python supplies NumPy on Windows.
The score lasts 48 seconds at 120 BPM, omitting every eighth clock pulse.
"""
from pathlib import Path
import json
import subprocess
import wave
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'Endless Runner/Music'
RATE=44100


def bell(frequency,duration=1.8):
    t=np.arange(int(RATE*duration))/RATE
    attack=np.minimum(t/.009,1)
    return attack*(np.sin(2*np.pi*frequency*t)*np.exp(-t*3.2)
                   +.23*np.sin(2*np.pi*frequency*2.01*t)*np.exp(-t*5.4)
                   +.07*np.sin(2*np.pi*frequency*4.02*t)*np.exp(-t*8))


def place(track,sound,at,gain=.2,pan=0):
    start=int(at*RATE)
    count=min(len(sound),len(track)-start)
    if count<=0:return
    balance=np.array([np.sqrt((1-pan)/2),np.sqrt((1+pan)/2)])
    track[start:start+count]+=sound[:count,None]*balance*gain


def write_wav(name,track):
    peak=np.max(np.abs(track))
    assert np.isfinite(track).all() and peak>0
    data=(np.clip(track/max(1,peak/.8),-.98,.98)*32767).astype('<i2')
    with wave.open(str(OUT/(name+'.wav')),'wb') as f:
        f.setnchannels(2);f.setsampwidth(2);f.setframerate(RATE);f.writeframes(data.tobytes())


def run():
    duration=48
    track=np.zeros((RATE*duration,2),dtype=np.float64)
    rng=np.random.default_rng(9876)
    chords=[[146.832,174.614,220],[116.541,146.832,174.614],
            [130.813,174.614,220],[130.813,164.814,195.998]]
    # Gentle sustained harmonics; crossfades leave space for the clockwork.
    for section,chord in enumerate(chords):
        span=13 if section<3 else 12
        t=np.arange(int(RATE*span))/RATE
        envelope=np.minimum(t/2,1)*np.minimum((span-t)/2,1)
        for index,freq in enumerate(chord):
            pad=(np.sin(2*np.pi*freq*t)+.25*np.sin(2*np.pi*(freq*1.003)*t))
            pad*=envelope*(.88+.12*np.sin(2*np.pi*.13*t+index))
            place(track,pad,section*12,.047,(index-1)*.5)
    for beat in range(96):
        if beat%8==7:continue  # One visibly/audibly absent timing segment.
        at=beat*.5
        chord=chords[min(3,beat//24)]
        freq=chord[(beat//2)%3]*(2 if beat%4 else 1)
        if beat%2==0:
            place(track,bell(freq),at,.15 if beat<16 else .19,.45*np.sin(beat*.7))
        t=np.arange(int(RATE*.11))/RATE
        tick=(np.sin(2*np.pi*1560*t)+.25*rng.normal(size=len(t)))
        tick*=np.minimum(t/.004,1)*np.exp(-t*65)
        place(track,tick,at,.03,(-1 if beat%2 else 1)*.30)
        if beat%4==0:
            t=np.arange(int(RATE*.45))/RATE
            low=np.sin(2*np.pi*(55*t+25*.025*(1-np.exp(-t/.025))))*np.exp(-t*8)
            place(track,low,at,.13,0)
    # The common three-note signature returns without supplying a fourth note.
    for phrase in [0,16,32,44]:
        for i,freq in enumerate([293.665,349.228,440]):
            place(track,bell(freq,2.4),phrase+i*.5,.13,(i-1)*.35)
    delay=int(.375*RATE)
    dry=track.copy()
    track[delay:,0]+=dry[:-delay,1]*.19
    track[delay:,1]+=dry[:-delay,0]*.19
    envelope=np.minimum(np.arange(len(track))/RATE/1.6,1)
    envelope*=np.minimum((len(track)-1-np.arange(len(track)))/RATE/1.2,1)
    track*=envelope[:,None]
    track*=.82/np.max(np.abs(track))
    path=OUT/'orbitGate.m4a'
    subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','f32le','-ar',str(RATE),
                    '-ac','2','-i','pipe:0','-c:a','aac','-b:a','192k',str(path)],
                   input=track.astype('<f4').tobytes(),check=True)
    motif=np.zeros((int(RATE*1.6),2))
    for i,freq in enumerate([293.665,349.228,440]):place(motif,bell(freq,1),i*.23,.42)
    write_wav('archiveSignal',motif)
    t=np.arange(int(RATE*1.65))/RATE
    noise=rng.normal(size=len(t))
    noise=np.convolve(noise,np.ones(85)/85,mode='same')
    thunder=(noise*2.8+.15*np.sin(2*np.pi*49*t)+.08*np.sin(2*np.pi*73*t))
    thunder*=np.minimum(t/.08,1)*np.exp(-t*2.1)*np.minimum((1.65-t)/.2,1)
    write_wav('archiveThunder',np.column_stack([thunder,thunder]))
    print(json.dumps({'score':str(path),'duration':duration,'peak':float(np.max(np.abs(track))),
                      'rms':float(np.sqrt(np.mean(track**2))),'missingClockBeats':12}))


if __name__=='__main__':run()
