"""Private demo state snapshots. Never commit generated snapshots or credentials."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tarfile
from datetime import datetime, timezone

BACKEND = Path(__file__).resolve().parents[1]
PUBLIC_AVATARS = Path('/var/www/docs/demo-assets/avatars')
TABLES = ('users', 'groups', 'group_members', 'workspaces', 'workspace_video_segments',
          'workspace_face_groups', 'workspace_face_records', 'agent_conversations', 'qa_records')


def connect():
    if os.environ.get('DATABASE_URL'):
        raise RuntimeError('This utility requires the default backend/user.db database.')
    con = sqlite3.connect(BACKEND / 'user.db', timeout=30)
    con.row_factory = sqlite3.Row
    con.execute('PRAGMA foreign_keys=ON')
    return con


def counts(con):
    return {name: con.execute(f'SELECT count(*) FROM {name}').fetchone()[0] for name in TABLES}


def assert_idle(con):
    if con.execute("SELECT count(*) FROM qa_records WHERE status='processing'").fetchone()[0]:
        raise RuntimeError('Wait for running investigations before taking a checkpoint.')
    if con.execute("SELECT count(*) FROM workspace_video_segments WHERE status='processing'").fetchone()[0]:
        raise RuntimeError('Wait for preprocessing before taking a checkpoint.')


def digest(file):
    h = hashlib.sha256()
    with open(file, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def snapshot(destination):
    destination = Path(destination).resolve()
    # The data disk is deliberately separate from the nearly full root filesystem.
    root = Path('/mnt/pureyes-recordings/checkpoints').resolve()
    if not destination.is_relative_to(root):
        raise RuntimeError(f'Checkpoint must be below {root}')
    destination.mkdir(parents=True, exist_ok=False, mode=0o700)
    with connect() as con:
        assert_idle(con)
        with sqlite3.connect(destination / 'user.db') as backup:
            con.backup(backup)
    with sqlite3.connect(destination / 'user.db') as backup:
        if backup.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
            raise RuntimeError('Database backup failed integrity check')
        state_counts = counts(backup)
    with tarfile.open(destination / 'assets.tar.gz', 'w:gz') as archive:
        paths = [BACKEND / 'temp', BACKEND / 'uploads', BACKEND / '.runtime', BACKEND / 'configs']
        paths += [p for p in (BACKEND / 'storage').iterdir() if p.name not in ('streams', 'live')]
        for path in paths:
            if path.exists():
                archive.add(path, arcname=str(Path('backend') / path.relative_to(BACKEND)),
                            filter=lambda entry: entry if entry.isfile() or entry.isdir() else None)
        if PUBLIC_AVATARS.exists():
            archive.add(PUBLIC_AVATARS, arcname='public-avatars')
    manifest = {
        'created_utc': datetime.now(timezone.utc).isoformat(),
        'backend_path': str(BACKEND), 'counts': state_counts,
        'sha256': {name: digest(destination / name) for name in ('user.db', 'assets.tar.gz')},
        'excluded': ['rolling monitor recordings', 'live HLS', 'model weights', 'systemd environment'],
        'privacy': 'Contains password hashes, private model configuration and face data. Keep private.',
    }
    (destination / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    for path in destination.iterdir():
        path.chmod(0o600)
    print(json.dumps({'checkpoint': str(destination), 'counts': state_counts}, ensure_ascii=False))


def seed(password):
    from werkzeug.security import generate_password_hash
    if len(password) < 12:
        raise RuntimeError('Demo password must be at least 12 characters')
    now = datetime.now(timezone.utc).replace(tzinfo=None).isoformat(' ')
    accounts = [
        ('demo_analyst', '林知远 · 分析员', 'user', 1, '#2563EB'),
        ('demo_patrol', '陈晓宁 · 巡查员', 'user', 1, '#0F766E'),
        ('demo_lead', '周明 · 协作管理员', 'admin', 1, '#7C3AED'),
        ('demo_newbie', '许安 · 待加入成员', 'user', 1, '#B45309'),
        ('demo_inactive', '演示停用账号', 'user', 0, '#64748B'),
    ]
    PUBLIC_AVATARS.mkdir(parents=True, exist_ok=True)
    for emp_id, _name, _role, _active, color in accounts + [('admin', '', '', 1, '#0C2942')]:
        # Original, non-photographic SVG avatars; no external image service or identity claims.
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="160" height="160" viewBox="0 0 160 160">'
               f'<rect width="160" height="160" rx="40" fill="{color}"/>'
               '<circle cx="80" cy="60" r="27" fill="#fff"/>'
               '<path d="M26 143c0-36 22-53 54-53s54 17 54 53" fill="#fff"/>'
               f'<circle cx="128" cy="30" r="12" fill="{color}" stroke="#fff" stroke-width="4"/></svg>')
        (PUBLIC_AVATARS / f'{emp_id}.svg').write_text(svg)
    with connect() as con:
        assert_idle(con)
        baseline = counts(con)
        if not con.execute("SELECT 1 FROM users WHERE emp_id='admin'").fetchone():
            raise RuntimeError('Existing admin account required')
        group = con.execute("SELECT id FROM groups WHERE name='test1' AND creator_id='admin'").fetchall()
        if len(group) != 1:
            raise RuntimeError('Expected exactly one admin-owned test1 group')
        group_id = group[0][0]
        for emp_id, name, role, active, _color in accounts:
            if con.execute('SELECT 1 FROM users WHERE emp_id=?', (emp_id,)).fetchone():
                raise RuntimeError(f'Demo account {emp_id} already exists; restore the checkpoint instead')
            con.execute('''INSERT INTO users(emp_id,name,password_hash,role,is_active,avatar,
                auth_version,screen_capture_allowed,created_at,updated_at) VALUES(?,?,?,?,?,?,0,0,?,?)''',
                (emp_id, name, generate_password_hash(password), role, active,
                 f'http://116.62.178.139/demo-assets/avatars/{emp_id}.svg', now, now))
        con.execute("UPDATE users SET avatar=?,updated_at=? WHERE emp_id='admin'",
                    ('http://116.62.178.139/demo-assets/avatars/admin.svg', now))
        for emp_id in ('demo_analyst', 'demo_patrol', 'demo_lead', 'demo_newbie'):
            con.execute('INSERT INTO group_members(group_id,emp_id,status,joined_at) VALUES(?,?,?,?)',
                        (group_id, emp_id, 'pending' if emp_id == 'demo_newbie' else 'accepted', now))
        con.execute('INSERT INTO workspaces(group_id,name,creator_id,created_at) VALUES(?,?,?,?)',
                    (group_id, '演示操作区 · 可创建和删除', 'admin', now))
        for name, creator in [('校园东门联合巡查 · 演示邀请', 'demo_lead'),
                              ('图书馆夜间值守 · 演示邀请', 'demo_patrol')]:
            cur = con.execute('INSERT INTO groups(name,creator_id,created_at) VALUES(?,?,?)', (name, creator, now))
            for emp_id, status in [(creator, 'accepted'), ('admin', 'pending'), ('demo_analyst', 'accepted')]:
                con.execute('INSERT INTO group_members(group_id,emp_id,status,joined_at) VALUES(?,?,?,?)',
                            (cur.lastrowid, emp_id, status, now))
        after = counts(con)
        for table in ('workspace_video_segments', 'workspace_face_groups', 'workspace_face_records',
                      'agent_conversations', 'qa_records'):
            if baseline[table] != after[table]:
                raise RuntimeError(f'Unexpected change to existing {table}')
        if con.execute('PRAGMA foreign_key_check').fetchall():
            raise RuntimeError('Foreign key verification failed')
    print(json.dumps({'seeded': True, 'counts': after}, ensure_ascii=False))


def verify(source):
    source = Path(source).resolve()
    manifest = json.loads((source / 'manifest.json').read_text())
    for name, expected in manifest['sha256'].items():
        if digest(source / name) != expected:
            raise RuntimeError(f'Checksum mismatch: {name}')
    with sqlite3.connect(source / 'user.db') as con:
        if con.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
            raise RuntimeError('Checkpoint database damaged')
        if counts(con) != manifest['counts']:
            raise RuntimeError('Checkpoint row counts mismatch')
    # Reject arbitrary archive paths and links before considering restoration.
    with tarfile.open(source / 'assets.tar.gz') as archive:
        for entry in archive:
            parts = Path(entry.name).parts
            if (not parts or parts[0] not in ('backend', 'public-avatars') or
                    '..' in parts or Path(entry.name).is_absolute() or
                    not (entry.isfile() or entry.isdir())):
                raise RuntimeError(f'Unsafe archive entry: {entry.name}')
            if parts[0] == 'backend' and (len(parts) < 2 or parts[1] not in
                    ('temp', 'uploads', '.runtime', 'configs', 'storage')):
                raise RuntimeError(f'Unexpected backend archive entry: {entry.name}')
            if parts[:3] in (('backend', 'storage', 'streams'), ('backend', 'storage', 'live')):
                raise RuntimeError('Rolling recordings must not be restored')
    print(json.dumps({'verified': str(source), 'counts': manifest['counts']}, ensure_ascii=False))


def restore(source, confirmed):
    if not confirmed:
        raise RuntimeError('Restore overwrites account/group/invitation/conversation state. Pass --confirm-restore.')
    if subprocess.run(['systemctl', 'is-active', '--quiet', 'pureyes-backend']).returncode == 0:
        raise RuntimeError('Stop pureyes-backend explicitly before restoring; this tool will not stop it for you.')
    verify(source)
    source = Path(source).resolve()
    if json.loads((source / 'manifest.json').read_text())['backend_path'] != str(BACKEND):
        raise RuntimeError('Checkpoint belongs to a different deployment path')
    # Before any replacement, retain another complete, private recovery checkpoint.
    safety = source.parent / ('before-restore-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    snapshot(safety)
    stage = source.parent / ('restore-stage-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    stage.mkdir(mode=0o700)
    try:
        with tarfile.open(source / 'assets.tar.gz') as archive:
            archive.extractall(stage)
        for tree in (stage / 'backend').iterdir():
            if tree.is_dir():
                shutil.copytree(tree, BACKEND / tree.name, dirs_exist_ok=True)
            else:
                shutil.copy2(tree, BACKEND / tree.name)
        if (stage / 'public-avatars').exists():
            shutil.copytree(stage / 'public-avatars', PUBLIC_AVATARS, dirs_exist_ok=True)
        # SQLite backup API replaces contents without leaving stale WAL pages.
        with sqlite3.connect(source / 'user.db') as src, connect() as dst:
            src.backup(dst)
    finally:
        shutil.rmtree(stage)
    print(json.dumps({'restored': str(source), 'safety_checkpoint': str(safety),
                      'note': 'Start backend, then sign in again. Rolling recordings and extra unreferenced files are retained.'}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('seed', 'snapshot', 'verify', 'restore'))
    parser.add_argument('--checkpoint')
    parser.add_argument('--confirm-restore', action='store_true')
    args = parser.parse_args()
    if args.action == 'seed':
        seed(os.environ['PUREYES_DEMO_PASSWORD'])
    elif not args.checkpoint:
        parser.error('--checkpoint is required')
    elif args.action == 'snapshot':
        snapshot(args.checkpoint)
    elif args.action == 'verify':
        verify(args.checkpoint)
    else:
        restore(args.checkpoint, args.confirm_restore)


if __name__ == '__main__':
    main()
