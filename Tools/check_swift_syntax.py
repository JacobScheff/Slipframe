"""Syntax-only fallback on Windows; this does NOT replace an Xcode build/XCTest.

uv run --with tree-sitter --with tree-sitter-swift python Tools/check_swift_syntax.py
"""
from pathlib import Path
from tree_sitter import Language, Parser
import tree_sitter_swift

ROOT = Path(__file__).resolve().parents[1]
parser = Parser(Language(tree_sitter_swift.language()))
failures = []
files = sorted((ROOT / 'Endless Runner').glob('*.swift')) + sorted((ROOT / 'Endless RunnerTests').glob('*.swift'))
for path in files:
    data = path.read_bytes()
    tree = parser.parse(data)
    if tree.root_node.has_error:
        stack = [tree.root_node]
        while stack:
            node = stack.pop()
            if node.type == 'ERROR' or node.is_missing:
                failures.append(f'{path.relative_to(ROOT)}:{node.start_point.row + 1}: {node.type} {data[node.start_byte:node.end_byte][:120]!r}')
            else:
                stack.extend(reversed(node.children))
if failures:
    raise SystemExit('\n'.join(failures))
print(f'Swift syntax check passed: {len(files)} files. Type checking and RealityKit execution still require Xcode.')
