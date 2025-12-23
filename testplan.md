# Section 1 — Direct-Mapped Cache

Configuration:
NUM_SETS = 256
NUM_WAYS = 1

| TC ID | Testcase Name       | Address Pattern       | Operation Sequence         | Expected Behavior           | Edge Case Covered  |
| ----- | ------------------- | --------------------- | -------------------------- | --------------------------- | ------------------ |
| DM-01 | Cold read miss      | Single address        | Read                       | Miss → fetch from memory    | Empty cache        |
| DM-02 | Write then read hit | Same address          | Write → Read               | Read returns written data   | Basic hit          |
| DM-03 | Conflict miss       | Same index, diff tag  | Write A → Write B → Read A | A evicted, miss on read     | Index conflict     |
| DM-04 | Write-back eviction | Same index            | Write A → Write B → Read B | B present, A written to RAM | Dirty eviction     |
| DM-05 | Sequential fill     | Sequential addresses  | Writes across cache        | All lines filled            | Full cache         |
| DM-06 | Full overwrite      | Same index loop       | Repeated writes            | Last write retained         | Thrashing          |
| DM-07 | Read after eviction | Evicted address       | Read                       | Data fetched from RAM       | Correct write-back |
| DM-08 | Address boundary    | Lowest & highest addr | Write → Read               | Correct data                | Address limits     |
| DM-09 | Alternating R/W     | Same line             | R/W toggling               | Stable data                 | Control logic      |
| DM-10 | Reset behavior      | After reset           | Read                       | Cache empty, miss           | Reset correctness  |

# Section 2 — 4-Way Set-Associative Cache

Configuration:
NUM_SETS = 64
NUM_WAYS = 4

| TC ID | Testcase Name          | Address Pattern  | Operation Sequence | Expected Behavior   | Edge Case Covered  |
| ----- | ---------------------- | ---------------- | ------------------ | ------------------- | ------------------ |
| SA-01 | Cold miss              | Single address   | Read               | Miss → memory fetch | Empty set          |
| SA-02 | Way fill               | Same set, 4 tags | Write 4 addresses  | All 4 ways valid    | Set capacity       |
| SA-03 | LRU eviction           | Same set, 5 tags | Write 5 addresses  | LRU evicted         | Replacement policy |
| SA-04 | Write-back on eviction | Dirty LRU        | Write → Evict      | Data written to RAM | Dirty line         |
| SA-05 | Hit after reuse        | Reused address   | Read               | Hit, no eviction    | LRU update         |
| SA-06 | Read all ways          | Same set         | Read all 4         | All hits            | Way selection      |
| SA-07 | Cross-set access       | Different sets   | Mixed R/W          | No interference     | Indexing           |
| SA-08 | Partial fill           | <4 ways          | Write 2 addresses  | No eviction         | Under-utilized set |
| SA-09 | Address boundary       | Max/min addr     | Write → Read       | Correct data        | Addr decode        |
| SA-10 | Reset behavior         | After reset      | Read               | Miss                | Reset              |


#Section 3 — Fully Associative Cache
Configuration:
NUM_SETS = 1
NUM_WAYS = 256

| TC ID | Testcase Name       | Address Pattern  | Operation Sequence  | Expected Behavior  | Edge Case Covered |
| ----- | ------------------- | ---------------- | ------------------- | ------------------ | ----------------- |
| FA-01 | Cold miss           | Single address   | Read                | Miss → fetch       | Empty cache       |
| FA-02 | Sequential fill     | Unique addresses | Write 256 addresses | Cache full         | Max capacity      |
| FA-03 | First eviction      | 257th address    | Write               | Oldest/LRU evicted | Full cache        |
| FA-04 | Write-back eviction | Dirty LRU        | Write → Evict       | RAM updated        | Dirty handling    |
| FA-05 | LRU accuracy        | Reused line      | Read → Evict others | Reused line stays  | LRU correctness   |
| FA-06 | Random access       | Random addresses | Mixed R/W           | Correct data       | Search logic      |
| FA-07 | Read after eviction | Evicted addr     | Read                | Data from RAM      | Memory coherence  |
| FA-08 | All-hits test       | Cached addrs     | Reads only          | All hits           | Tag compare       |
| FA-09 | Address boundary    | Min/max addr     | Write → Read        | Correct data       | Decoder           |
| FA-10 | Reset behavior      | After reset      | Read                | Miss               | Reset             |
