# LLM Testing Status - 2026-07-26

## Working ✅

### RTX 5060 Ti (Host) - FULLY OPERATIONAL
- **vLLM**: 0.22.1 running on port 8000
- **Model**: Qwen3-4B-Instruct (Qwen/Qwen3-4B, 7.6GB safetensors)
- **Benchmark**: 1006 tok/s peak @ 24 concurrent

```
Concurrency 1:   ~48 tok/s
Concurrency 2:   ~94 tok/s  
Concurrency 4:   ~188 tok/s
Concurrency 8:   ~370 tok/s
Concurrency 12:  ~547 tok/s
Concurrency 16:  ~722 tok/s
Concurrency 24:  ~1006 tok/s (peak)
```

### llama.cpp on Host
- Build: `/home/mkinney/Repos/llama.cpp/build-cuda/`
- CUDA: Supported (RTX 5060 Ti)

## Not Working ❌

### Qwen3.6 35B REAP GGUF
- Model: `/home/mkinney/Models/JZC973/Qwen3.6-35B-REAP-MTP-UD-GGUF-Collection/Qwen3.6-35B-A3B-UD-Q3_K_XL-REAP.gguf`
- Size: 13GB
- **Error**: Out of memory - requires ~20GB+ memory, only ~5GB available
- **vLLM 0.22.1 doesn't support GGUF format natively**

### Tesla V100 (VM) - UBUNTU 22.04 SETUP IN PROGRESS

#### What Was Done
- [x] Downloaded Ubuntu 22.04.5 Server ISO (2.0GB)
- [x] Created 100GB QCOW2 disk image
- [x] Created cloud-init ISO
- [x] Created VM startup script

#### Files Created
```
/home/mkinney/vm-images/
├── ubuntu-22.04-server.iso        # Ubuntu 22.04.5 Server ISO (2GB)
├── ubuntu-22.04-vm.qcow2          # 100GB disk for VM
├── ubuntu-22.04-cloud-init.iso    # Cloud-init config
├── run_ubuntu2204_v100.sh         # VM startup script
└── SETUP_UBUNTU2204_V100.md       # Full setup guide
```

#### What YOU Need To Do (When You Wake Up)

1. **Kill old VM**: `sudo pkill -f qemu-system-x86`

2. **Start installer**: 
   ```bash
   cd /home/mkinney/vm-images && ./run_ubuntu2204_v100.sh
   ```

3. **Connect VNC** to `127.0.0.1:5901`

4. **Install Ubuntu 22.04** (follow prompts - use entire disk, user: mkinney, pass: S1lence13!)

5. **After install**, I'll provide the modified boot script (remove `-cdrom` to boot from disk)

6. **Once Ubuntu is running**, I'll SSH in and install CUDA 11.x, vLLM, and run benchmarks

Full instructions at: `/home/mkinney/vm-images/SETUP_UBUNTU2204_V100.md`

## Commands Reference

### Test vLLM (Host)
```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"...","messages":[{"role":"user","content":"Hi"}],"max_tokens":50}'
```

### Kill/Start vLLM (Host)
```bash
pkill -f "vllm serve"
cd /home/mkinney && HF_HUB_OFFLINE=1 vllm serve ...
```
