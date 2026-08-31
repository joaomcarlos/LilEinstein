# abucnasty Video Transcripts

Transcripts of 13 abucnasty Factorio videos, fetched via TranscriptAPI.com
and saved as readable text files for reference by the LilEinstein project
skills.

These transcripts are the primary source material for the abucnasty
knowledge skills in `.devin/skills/`:

- `factorio-abucnasty-science` — ESPM formula, caps, weights, quality recs
- `factorio-abucnasty-lab-design` — lab clocking, inserters, UPS benchmarks
- `factorio-abucnasty-megabase-logistics` — planet strategy, spoilage, ships
- `factorio-fff443-research-control` — Factorio 2.1 circuit lab control

## Transcript index

| File | Video title | Lines | Chars |
|------|-------------|-------|-------|
| `01_what_is_espm.txt` | What is ESPM? How I define a Megabase | 780 | 37k |
| `02_fin_2.5m_espm.txt` | Fin [2.5 Million ESPM Megabase] | 921 | 41k |
| `03_aquilo_prom.txt` | Aquillo & Prom [Road to 2.5 Million ESPM] | 1455 | 69k |
| `04_gleba.txt` | Gleba [Road to 2.5 Million ESPM] | 1349 | 64k |
| `05_nauvis_vulcanus_space.txt` | Nauvis & Vulcanus & Space [Road to 2.5 Million ESPM] | 2041 | 96k |
| `06_4m_spm_tour.txt` | Factorio Space Age: 4 million SPM Mega Base Tour | 2996 | 141k |
| `07_ups_labs.txt` | UPS Optimizations: Labs | 2268 | 108k |
| `08_labs_finale.txt` | Labs Finale (Part 1) | 1320 | 62k |
| `09_hub_redesign_lab_clocking.txt` | Hub Redesign & Lab Clocking Experiments | 2052 | 97k |
| `10_quality_space_science.txt` | Which Quality Space Science is best for UPS? | 1775 | 80k |
| `11_quality_core_sciences.txt` | Quality Science Conclusion: Core Sciences | 1453 | 65k |
| `12_fff443_unlimited_throughput.txt` | FFF-443: Unlimited Throughput | 999 | 46k |
| `13_gleba_science_monitor.txt` | Gleba Science Monitor | 874 | 39k |

## Format

Each file has a metadata header (title, channel, video ID, fetch date),
followed by the transcript text split into ~6000-char chunks. Timestamps
are embedded in the text as `[Xs]` markers.

## Re-fetching

To re-fetch or add new transcripts, use the `youtube-full` skill and the
`youtube-research-apply` skill workflow. The API key is stored in
`~/.bashrc` as `TRANSCRIPT_API_KEY`.
