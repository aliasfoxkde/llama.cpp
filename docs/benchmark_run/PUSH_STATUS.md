# Git Push Status

## Commits Ready to Push

Branch: `feature/apu-benchmarks-2026`

**4 commits to push:**
```
6550b9d0c docs: update benchmark docs with Escha SGLang Blackwell findings
0ed80b1ee docs: add Escha SGLang baseline results for RTX 5060 Ti
d21d2db02 docs: update results with Escha SGLang baseline
240de0627 docs: update with Escha SGLang throughput and vLLM blocked findings
```

## Authentication Issues

1. **SSH key not authorized**: `git@github.com: Permission denied (publickey)`
2. **GitHub CLI token invalid**: `gh auth status` shows token for `aliasfoxkde` is invalid

## To Fix - Run These Commands:

```bash
# Option 1: Re-authenticate GitHub CLI
gh auth logout -h github.com -u aliasfoxkde
gh auth login -h github.com

# Option 2: Switch to HTTPS with personal access token
# Generate token at: https://github.com/settings/tokens
git remote set-url origin https://github.com/aliasfoxkde/llama.cpp.git
# Then push will prompt for token

# Option 3: Add SSH key to GitHub
# Copy your public key:
cat ~/.ssh/id_ed25519.pub
# Add at: https://github.com/settings/keys
```

## After Fix, Push With:
```bash
git push origin feature/apu-benchmarks-2026
```
