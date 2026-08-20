Can you try this one: https://huggingface.co/YTan2000/Qwen3.8-27B-TQ3_4S/
With the v2 model (Qwen3.8-27B-TQ3_4S-v2.gguf), the Chat Template (chat_template.jinja), and Vision Encoder (mmproj-BF16.gguf)?


For testing, can we try:
https://huggingface.co/unsloth/Qwen3.8-27B-GGUF, wtih
UD-IQ2_XXS (9.01GB) to reduce overhead with MTP, and also test it with the DSpark 2.72GB model:
https://huggingface.co/RadixArk/Qwen3.8-27B-DSpark

Running in
sglang serve \
  --trust-remote-code \
  --model-path Qwen/Qwen3.8-27B-FP8 \
  --tp-size 1 \
  --speculative-algorithm DSPARK \
  --speculative-draft-model-path RadixArk/Qwen3.8-27B-DSpark \
  --speculative-dspark-block-size 7 \
  --speculative-draft-model-quantization unquant \
  --mamba-scheduler-strategy extra_buffer \
  --attention-backend fa3

Either Qwen3.8 27B TQ3_4S or IQ3_XXS work well (close to original accuracy), and we can run Qwen3.8 35B A3B but it's probably half the intellegence...
So if 2Bit can be fast, then it's probably better than using the older 3.6 version, even at the quant for "fast" model... and IQ3_XXS for intellegence.
If it can support either MTP or DSpark, etc.



START FUCKING LISTENING TO THE GOD DAMN FUCKING WORDS I AM SAYING...
https://huggingface.co/unsloth/Qwen3.8-27B-GGUF (UD-IQ2_XXS @ 9.01GB) WITH
https://huggingface.co/magnitudedev/Qwen3.8-27B-DSpark-GGUF (Q8_0 @ 1.46GB)

And I'm assuming llama.cpp will work? Thoughts?


Theory:
Qwen3.8-Pro (UD-IQ3_XXS @ 11.9GB; No-MTP K/V Q4_0 and CTX 128K; ~30tps)
- https://huggingface.co/unsloth/Qwen3.8-27B-GGUF 
Qwen3.8-Flash (UD-IQ2_XXS @ 9.01GB w/ MTP=3 and K/V Q4_0 & CTX 96K-256K; ~63-58tps)
- https://huggingface.co/unsloth/Qwen3.8-27B-GGUF; or
Qwen3.8-Flash (UD-IQ2_XXS @ 9.01GB w/ DSpark Q8_0 @ 1.46GB = ~10.47GB K/V Q4_0 & CTX 96K; 77tps);
- https://huggingface.co/unsloth/Qwen3.8-27B-GGUF
- https://huggingface.co/magnitudedev/Qwen3.8-27B-DSpark-GGUF
Qwen3.6-UltraFast (Qwen3.6-35B-A3B-UD-IQ3_S-REAP.gguf @ 12GB; 95tps and 215tps for 4 concurrency)
- https://huggingface.co/JZC973/Qwen3.6-35B-REAP-MTP-UD-GGUF-Collection

Note:
- DSpark is too much overhead and can't go over 96K CTX
- TQ3_4S can be ~50tps with MTP, but max 32K
- Needs ~1gb for vision encoder (mmproj-BF16.gguf)
- Both must support vision

Best Numbers
┌───────────────┬──────────────────┬──────┬────────────┬──────────────────────────────────┐
│   Priority    │      Config      │ CTX  │ Throughput │              Notes               │
├───────────────┼──────────────────┼──────┼────────────┼──────────────────────────────────┤
│ 🥇 Best Speed │ IQ2_XXS + DSpark │ 96K  │ 77 tok/s   │ Requires TQ3 fork, 9GB base      │
├───────────────┼──────────────────┼──────┼────────────┼──────────────────────────────────┤
│ 🥈 Large CTX  │ IQ2_XXS + MTP    │ 96K  │ 63 tok/s   │ Better than DSpark for stability │
├───────────────┼──────────────────┼──────┼────────────┼──────────────────────────────────┤
│ 🥉 128K Only  │ IQ3_XXS alone    │ 128K │ ~30 tok/s  │ Stock llama.cpp, no spec         │
├───────────────┼──────────────────┼──────┼────────────┼──────────────────────────────────┤
│ ⚡ Vision     │ TQ3_4S V2 + MTP  │ 16K  │ 44 tok/s   │ Multimodal support               │
└───────────────┴──────────────────┴──────┴────────────┴──────────────────────────────────┘

Test IQ2_XXS + MTP (2-8) at 96K (if passes, also try higher 128K, 140K, 164K, 200K 256K) and K/V at Q4_0... take the best speeds and test concurrency (2-8)...
I want to know the numbers for IQ2_XXS with DSpark with 3,5,6,7 draft tokens as well... so the ENTIRE 2-8 range (say for 96K CTX).


Can we "distill"/knowledge transfer Qwen/Qwen3.8-2.4T-A95B (or try Qwen3.8 27B) to Qwen/Qwen3.5-9B (UD-Q4_K_XL @ 5.97GB)? 
- And/or Qwen3.5 4B/2B/0.8B and benchmark the models/results
- And does including "knowledge" from Kimi-K3, GLM-5.3, and others improve the "student" model?
