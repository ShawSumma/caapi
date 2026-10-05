import math
import sys

BOUNDING_SPHERE_RADIUS = 1.2264568712514068
GAUSS_NODES = [(-math.sqrt(3 / 5), 5 / 9), (0.0, 8 / 9), (math.sqrt(3 / 5), 5 / 9)]

type Knots = list[float]


def corner_coordinate() -> float:
    return math.tanh(BOUNDING_SPHERE_RADIUS) / math.sqrt(3)


def box_volume(low: tuple[float, float, float], high: tuple[float, float, float]) -> float:
    half = [(high[axis] - low[axis]) / 2 for axis in range(3)]
    middle = [(high[axis] + low[axis]) / 2 for axis in range(3)]
    total = 0.0
    for xi, xw in GAUSS_NODES:
        for yi, yw in GAUSS_NODES:
            for zi, zw in GAUSS_NODES:
                point = [middle[0] + half[0] * xi, middle[1] + half[1] * yi, middle[2] + half[2] * zi]
                radius_squared = sum(p * p for p in point)
                total += xw * yw * zw / (1 - radius_squared) ** 2
    return total * half[0] * half[1] * half[2]


def volumes(knots: Knots) -> list[float]:
    scale = corner_coordinate()
    planes = [scale * k for k in knots]
    cells = len(knots) - 1
    result = []
    for x in range(cells):
        for y in range(cells):
            for z in range(cells):
                result.append(box_volume((planes[x], planes[y], planes[z]), (planes[x + 1], planes[y + 1], planes[z + 1])))
    return result


def spread(knots: Knots) -> float:
    found = volumes(knots)
    return max(found) / min(found)


def uniform(cells: int) -> Knots:
    return [i / cells for i in range(cells + 1)]


def improved(knots: Knots, step: float) -> Knots:
    best = spread(knots)
    for index in range(1, len(knots) - 1):
        for direction in (-1, 1):
            trial = list(knots)
            trial[index] += direction * step
            if trial[index - 1] < trial[index] < trial[index + 1]:
                trial_spread = spread(trial)
                if trial_spread < best:
                    knots = trial
                    best = trial_spread
    return knots


def optimized(start: Knots, rounds: int) -> Knots:
    knots = start
    step = 0.1 / len(start)
    for _ in range(rounds):
        previous = None
        while previous != knots:
            previous = knots
            knots = improved(knots, step)
        step /= 2
    return knots


def geometric(cells: int, ratio: float) -> Knots:
    widths = [ratio**i for i in range(cells)]
    total = sum(widths)
    knots = [0.0]
    for width in widths:
        knots.append(knots[-1] + width / total)
    return knots


def klein_distance(p: list[float], q: list[float]) -> float:
    dot = sum(a * b for a, b in zip(p, q))
    pp = sum(a * a for a in p)
    qq = sum(b * b for b in q)
    return math.acosh((1 - dot) / math.sqrt((1 - pp) * (1 - qq)))


def edge_meters(knots: Knots) -> tuple[float, float, float]:
    scale = corner_coordinate()
    planes = [scale * k for k in knots]
    cells = len(knots) - 1
    meter = (sum(volumes(uniform(cells))) / cells**3) ** (1 / 3)
    shortest = math.inf
    longest = 0.0
    worst_aspect = 1.0
    for x in range(cells):
        for y in range(cells):
            for z in range(cells):
                low = [planes[x], planes[y], planes[z]]
                high = [planes[x + 1], planes[y + 1], planes[z + 1]]
                center = [(low[axis] + high[axis]) / 2 for axis in range(3)]
                edges = []
                for axis in range(3):
                    a = list(center)
                    b = list(center)
                    a[axis] = low[axis]
                    b[axis] = high[axis]
                    edges.append(klein_distance(a, b) / meter)
                shortest = min(shortest, min(edges))
                longest = max(longest, max(edges))
                worst_aspect = max(worst_aspect, max(edges) / min(edges))
    return shortest, longest, worst_aspect


def best_geometric(cells: int, samples: int) -> tuple[float, Knots]:
    candidates = [0.80 + 0.2 * i / samples for i in range(samples + 1)]
    ratio = min(candidates, key=lambda r: spread(geometric(cells, r)))
    return ratio, geometric(cells, ratio)


def main() -> None:
    cells = int(sys.argv[1])
    rounds = int(sys.argv[2])
    print(f"chunk volume {sum(volumes(uniform(cells))):.9f}")
    print(f"uniform spread {spread(uniform(cells)):.3f}")
    shortest, longest, aspect = edge_meters(uniform(cells))
    print(f"uniform edges {shortest:.2f}..{longest:.2f} m, aspect up to {aspect:.2f}")
    ratio, knots = best_geometric(cells, 40)
    print(f"geometric ratio {ratio:.4f} spread {spread(knots):.3f}")
    shortest, longest, aspect = edge_meters(knots)
    print(f"geometric edges {shortest:.2f}..{longest:.2f} m, aspect up to {aspect:.2f}")
    knots = optimized(knots, rounds)
    print(f"optimized spread {spread(knots):.3f}")
    print("knots " + " ".join(f"{k:.5f}" for k in knots))


main()
