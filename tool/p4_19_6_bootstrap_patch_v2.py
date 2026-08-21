from pathlib import Path

source = Path('tool/p4_19_6_bootstrap_patch.py').read_text()
old = """# 4) Version authority.\nfor path in [\n    'pubspec.yaml',\n    'lib/features/invoice/lab/private_cloud_invoice_lab_config.dart',\n    'test/p4_12_34_1_version_contract_test.dart',\n    'test/p4_12_38_exact_head_test.dart',\n]:\n    replace_once(path, '4.19.5+442', '4.19.6+443')\n"""
new = """# 4) Version authority.\nfor path in [\n    'pubspec.yaml',\n    'lib/features/invoice/lab/private_cloud_invoice_lab_config.dart',\n    'test/p4_12_38_exact_head_test.dart',\n]:\n    replace_once(path, '4.19.5+442', '4.19.6+443')\n\nversion_contract = Path('test/p4_12_34_1_version_contract_test.dart')\nversion_text = version_contract.read_text()\nversion_count = version_text.count('4.19.5+442')\nif version_count != 2:\n    raise SystemExit(\n        f'test/p4_12_34_1_version_contract_test.dart: expected two version matches, got {version_count}'\n    )\nversion_contract.write_text(version_text.replace('4.19.5+442', '4.19.6+443'))\n"""
count = source.count(old)
if count != 1:
    raise SystemExit(f'bootstrap v2 expected one version block, got {count}')
patched = source.replace(old, new, 1)
exec(compile(patched, 'tool/p4_19_6_bootstrap_patch.py', 'exec'), {'__name__': '__main__'})
