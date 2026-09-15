#!/usr/bin/env python3
"""Export native Godot games and bundle a pinned, authenticated local Node bridge.

Run on macOS with Python 3, Godot 4.5.1 and its matching export templates.
Downloads only official Node/Godot files; never reads .env or player saves.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request
import zipfile

PROJECT = Path(__file__).resolve().parents[1]
ROOT = PROJECT.parents[1]
CACHE = PROJECT / '.local/release-cache'
BUILD = PROJECT / 'build/desktop'
VERSION = '22.23.2'
NODE_HASHES = {
    'darwin-arm64': '61130f394c1630d211dd50aecc4353d379480f36d3ac913cd85dbba1aed585c6',
    'darwin-x64': '58e99022c2ff89395576cc7fd4d98cea24bb68081475d5f88b801ee8729fb026',
    'linux-x64': 'b294a556e639d64338823920e5866c21c02741742d2e1529ee1a225c1ec9252a',
    'win-x64': '1177b4137ba5adaa56354ae40f1080c7450e8ae09cecb47da459d1c52ac99f97',
}

README = '''SEEDLAB — Button Garden / Native preview 1.0.0
Team qqpann · Qiushi Pan
https://github.com/qqpann/hachathon_openai100

【起動】
ZIP / tar.gz 全体を展開してください。Godot・Node.jsの別途インストールは不要です。
macOS: SEEDLAB.app を開く（Apple Silicon / Intel、macOS 11以降）。
Windows x64: SEEDLAB.exe を開く。「seedlab」フォルダも同じ場所に置いてください。
Linux x64: ./SEEDLAB.x86_64 を実行。「seedlab」フォルダも同じ場所に置いてください。
Mac版は開発者署名・公証をしていません。OSに止められた場合は、内容を確認した上で
システム設定の「プライバシーとセキュリティ」から許可してください。
Windows版もコード署名はありません。

【遊ぶ】
手書き数字を読んで、右の0〜9ボタンで教える → Gを得る → 左の3D強化盤を押す。
学び方Lv.1: SpaceでNNに任せる。Lv.2: Aで自動練習。Lv.3: Rで育成を委任。
T: 認定試験、V: 入力カメラ切替、F: 作業台へ戻る、H: 遊び方。
ゲームと小さなNNの学習はAPIキーなしでも動きます。進行は自動保存します。

【OpenAIコーチ / Bring Your Own Token】
画面右の「APIキーを設定・解除」から自分のOpenAI APIキーを入力してください。
設定後、育成委任を解放し、24回練習してRを押すとOpenAIに相談します。
料金は入力したキーのOpenAIアカウントにかかります。ChatGPTの契約とは別です。
キーはこの起動中だけローカル接続サービスのメモリで保持し、保存しません。
「キーを破棄」またはゲーム終了で破棄。毎回の起動時に入力してください。
gpt-5.4-nano、最大400出力トークン、最大4回/分・20回/起動。
成績・購入候補・強化盤の画像をOpenAIに送ります。自動再試行はありません。
これらの回数制限はOpenAIアカウント全体の支出上限ではありません。

【English quick start】
Extract the entire archive. Open the app / executable for your OS; keep the
seedlab folder beside the Windows/Linux executable. Godot and Node are bundled.
Teach MNIST digits with the numbered 3D buttons, earn G, and buy upgrades on the
left physical board. The interface is in Japanese. H opens the control guide.
The neural learner works offline. Optional coaching uses your own OpenAI API key:
the bottom-right API-key button opens a masked input. Unlock Learning level 3,
complete 24 practice trials, then press R. API usage is billed to your API account.
The key is kept only for this launch, never saved to disk or shipped in the app.
macOS is ad-hoc signed, not Developer ID signed or notarized. Windows is unsigned.

This release adds native packaging and BYOT support after the hackathon deadline.
The original Sep 15 submission is preserved at tag submission-2026-09-15.
Third-party notices are in LICENSES/ and seedlab/runtime/ (macOS: inside the app).
'''


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def download(url, path):
    if not path.exists():
        temporary = path.with_suffix(path.suffix + '.download')
        urllib.request.urlretrieve(url, temporary)
        temporary.replace(path)
    return path


def bundle_node(target, variant, executable):
    extension = 'zip' if variant.startswith('win') else 'tar.gz'
    prefix = f'node-v{VERSION}-{variant}'
    archive = download(f'https://nodejs.org/dist/v{VERSION}/{prefix}.{extension}', CACHE / f'{prefix}.{extension}')
    if digest(archive) != NODE_HASHES[variant]:
        raise RuntimeError(f'Node checksum mismatch: {archive.name}')
    target.mkdir(parents=True, exist_ok=True)
    if extension == 'zip':
        with zipfile.ZipFile(archive) as source:
            (target / executable).write_bytes(source.read(prefix + '/node.exe'))
            (target / f'LICENSE-{variant}.txt').write_bytes(source.read(prefix + '/LICENSE'))
    else:
        with tarfile.open(archive) as source:
            for member, output in [('bin/node', executable), ('LICENSE', f'LICENSE-{variant}.txt')]:
                with source.extractfile(prefix + '/' + member) as stream:
                    with (target / output).open('wb') as destination:
                        shutil.copyfileobj(stream, destination)
    (target / executable).chmod(0o755)


def support_files(target, variants):
    # Explicit allowlist: no environment files, saves, logs or source recordings.
    for name in ['prototypes/seedlab-godot/bridge/server.mjs',
                 'prototypes/seedlab-godot/data/upgrades.json', 'server/usage-policy.js']:
        destination = target / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, destination)
    (target / 'package.json').write_text(json.dumps({'private': True, 'type': 'module'}) + '\n')
    for variant, executable in variants:
        bundle_node(target / 'runtime', variant, executable)


def notices(folder):
    (folder / 'README.txt').write_text(README, encoding='utf-8')
    target = folder / 'LICENSES'
    target.mkdir(exist_ok=True)
    for name in ['LICENSE', 'COPYRIGHT']:
        source = download(f'https://raw.githubusercontent.com/godotengine/godot/4.5.1-stable/{name}.txt', CACHE / f'Godot-{name}.txt')
        shutil.copy2(source, target / source.name)
    shutil.copy2(PROJECT / 'assets/fonts/OFL.txt', target / 'Noto-CJK-OFL.txt')
    shutil.copy2(PROJECT / 'data/mnist/README.md', target / 'MNIST.md')
    shutil.copy2(PROJECT / 'data/mnist/manifest.json', target / 'MNIST-manifest.json')
    (target / 'COMPONENTS.txt').write_text('Godot 4.5.1: MIT and bundled third-party notices.\n'
        f'Node.js {VERSION}: MIT and bundled notices in runtime/LICENSE-*.txt.\n'
        'Noto Sans CJK JP: SIL Open Font License 1.1, unmodified.\n'
        'MNIST: Yann LeCun, Corinna Cortes, Christopher J. C. Burges. See MNIST.md.\n'
        'Blender (GPL-2.0-or-later) and Blender MCP (MIT) were authoring tools only.\n'
        'OpenAI API and Codex are services under their applicable terms.\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', '/Applications/Godot.app/Contents/MacOS/Godot'))
    parser.add_argument('--skip-export', action='store_true', help='Package already exported executables')
    args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    BUILD.mkdir(parents=True, exist_ok=True)
    (PROJECT / 'build/.gdignore').touch()
    if not args.skip_export:
        for preset, folder in [('macOS', 'macos'), ('Windows', 'windows'), ('Linux', 'linux')]:
            (BUILD / folder).mkdir(exist_ok=True)
            print(f'Exporting {preset}', flush=True)
            with (BUILD / f'{folder}-export.log').open('w') as log:
                subprocess.run([args.godot, '--headless', '--path', str(PROJECT), '--export-release', preset], stdout=log, stderr=subprocess.STDOUT, check=True)
    staging = BUILD / 'packages'
    outputs = BUILD / 'releases'
    staging.mkdir(exist_ok=True)
    outputs.mkdir(exist_ok=True)
    assets = []
    for label, folder, entry, variants in [
        ('macOS-universal', 'macos', 'SEEDLAB.app', [('darwin-arm64', 'node-arm64'), ('darwin-x64', 'node-x64')]),
        ('Windows-x64', 'windows', 'SEEDLAB.exe', [('win-x64', 'node.exe')]),
        ('Linux-x64', 'linux', 'SEEDLAB.x86_64', [('linux-x64', 'node')]),
    ]:
        print(f'Packaging {label}', flush=True)
        package = staging / f'SEEDLAB-{label}'
        if package.exists():
            shutil.rmtree(package)
        package.mkdir()
        game = package / entry
        if entry.endswith('.app'):
            shutil.copytree(BUILD / folder / entry, game)
            support = game / 'Contents/Resources/seedlab'
        else:
            shutil.copy2(BUILD / folder / entry, game)
            game.chmod(0o755)
            support = package / 'seedlab'
        support_files(support, variants)
        notices(package)
        if entry.endswith('.app'):
            subprocess.run(['/usr/bin/codesign', '--force', '--deep', '--sign', '-', str(game)], check=True)
            subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(game)], check=True)
        suffix = '.tar.gz' if folder == 'linux' else '.zip'
        archive = outputs / (package.name + '-v1.0.0' + suffix)
        archive.unlink(missing_ok=True)
        if folder == 'macos':
            subprocess.run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(package), str(archive)], check=True)
        elif folder == 'linux':
            with tarfile.open(archive, 'w:gz', compresslevel=6) as target:
                target.add(package, arcname=package.name)
        else:
            with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as target:
                for path in sorted(package.rglob('*')):
                    if path.is_file():
                        target.write(path, path.relative_to(staging))
        assets.append(archive)
        print(f'{archive.name}: {archive.stat().st_size:,} bytes', flush=True)
    (outputs / 'SHA256SUMS.txt').write_text(''.join(f'{digest(path)}  {path.name}\n' for path in assets))
    print(f'Release files: {outputs}', flush=True)


if __name__ == '__main__':
    main()
