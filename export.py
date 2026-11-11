
import glob

srcs = []

srcs.append('dub.sdl')
srcs.extend(glob.glob('plugins/**/*.d', recursive=True))
srcs.extend(glob.glob('source/**/*.c', recursive=True))
srcs.extend(glob.glob('source/**/*.d', recursive=True))
srcs.extend(glob.glob('source/**/*.frag', recursive=True))
srcs.extend(glob.glob('source/**/*.h', recursive=True))
srcs.extend(glob.glob('source/**/*.vert', recursive=True))
# srcs.extend(glob.glob('web/**/*.d', recursive=True))
# srcs.extend(glob.glob('web/**/*.html', recursive=True))
# srcs.extend(glob.glob('web/**/*.js', recursive=True))
# srcs.extend(glob.glob('web/**/*.syms', recursive=True))

srcs.sort()

lines = []
for i, src in enumerate(srcs):
    if i != 0:
        lines.append('\n')
    name = src.removeprefix('src/')
    lines.append(f'/// file: {name}\n')
    with open(src) as f:
        lines.append(f.read().strip())
    lines.append('\n')

with open('export.txt', 'w') as f:
    f.writelines(lines)
