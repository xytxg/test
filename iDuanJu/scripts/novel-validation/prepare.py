"""Build a macOS CLI around the app's actual Legado engine, without the player SDKs."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
dest = Path(sys.argv[1]).resolve()
dest.mkdir(parents=True, exist_ok=True)
for name in ['LegadoCore.swift', 'LegadoRule.swift', 'LegadoJSONPath.swift', 'LegadoClient.swift', 'LegadoSource.swift']:
    (dest / name).write_text((root / 'STV/Novel/Legado' / name).read_text('utf8'), 'utf8')
html = (root / 'STV/Plugins/PluginHTML.swift').read_text('utf8')
(dest / 'CSSXPath.swift').write_text(html[:html.index('/// libxml2 HTML documents')], 'utf8')
login = (root / 'STV/Novel/Legado/LegadoLogin.swift').read_text('utf8')
(dest / 'SourceState.swift').write_text(login[:login.index('/// WebKit cookies')].replace('import UIKit', '').replace('import WebKit', ''), 'utf8')
novel = (root / 'STV/Novel/NovelImport.swift').read_text('utf8')
start = novel.index('    static func normalize(')
end = novel.index('\n    }', start) + 6
entities = novel[novel.index('    static func decodeEntities('):novel.index('/// Read-only ZIP')]
(dest / 'Text.swift').write_text(novel, 'utf8')
store = (root / 'STV/Novel/NovelStore.swift').read_text('utf8')
(dest / 'NovelStore.swift').write_text(store[:store.index('/// Reader appearance')], 'utf8')
(dest / 'UnsupportedBrowser.swift').write_text('''import Foundation
enum LegadoBrowser {
    static func openBlocking(url: URL?, html: String?, title: String, sourceURL: String) {}
    @MainActor static func open(url: URL?, html: String?, title: String, sourceURL: String) async {}
}
enum LegadoWebView {
    static func run(html: String?, url: String?, js: String?) throws -> String {
        throw LegadoError.rule("requires interactive WebView; unavailable in command-line validation")
    }
}
''', 'utf8')
