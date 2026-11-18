"""Keep the Kotlin sandbox prelude identical to the production Swift runtime."""
from pathlib import Path

root = Path(__file__).resolve().parents[2]
source = (root / 'STV/Novel/Legado/LegadoCore.swift').read_text('utf8')
start = source.index('(function (') if '(function (' in source else source.index('(function(')
end = source.index('})(__host);', start) + len('})(__host);')
(root / 'android/core/src/main/resources/novel-prelude.js').write_text(source[start:end] + '\n', 'utf8')
