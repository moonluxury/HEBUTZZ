"""Package unmodified, real Godot frames into a GIF using captured frame timings."""
import json
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1] / 'outputs/discussion-validation'
trace = json.loads((root / 'motion-trace.json').read_text(encoding='utf-8'))
for direction in ['open', 'close']:
    samples = [row for row in trace if row['direction'] == direction]
    frames, durations = [], []
    for i, row in enumerate(samples):
        frames.append(Image.open(root / f'motion-{direction}-{row["frame"]:02d}.png').convert('RGB'))
        durations.append(max(10, samples[i+1]['elapsed_ms']-row['elapsed_ms']) if i+1 < len(samples) else 1000)
    frames[0].save(root / f'motion-{direction}.gif', save_all=True, append_images=frames[1:], duration=durations, loop=0, optimize=False)
    print(direction, len(frames), 'real frames; first fully visible destination at',
          next((s['elapsed_ms'] for s in samples if s['discussion_alpha' if direction=='open' else 'numbers_alpha'] == 1), 'after captured interval'), 'ms')
