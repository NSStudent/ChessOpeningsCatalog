# Measurement on LumbrasGigabase_OTB_2025.pgn

- Games: 492184; with a starting FEN (not classified): 0; without moves: 2; replay stopped by an unplayable move before ply 40: 2 (classified with the keys that were played).
- Classifiable: 492182; with an ECO tag: 392747 (79.80 %); without: 99435.
- Replay of the first 40 plies with FischerCore: 51.6 s in 10 processes.

## Resource and loading

- `openings.bin`: 213986 bytes; 3865 named positions and 141 transpositions.
- Loading `OpeningCatalog.shared` (read + hash table): 19.03 ms.

## Time of `classify` per game

39.3 keys per game on average (up to 40 plies); all 492182 games in blocks of 2,048 with their keys in cache (best of 3 passes per block), one core:

| Variant | ns/game |
|---|---|
| `classifyIndex(keys:)` on a buffer, with transpositions | 306 |
| `classifyIndex(keys:matching: .namedPositions)` | 303 |
| `classifyMatch(keys:)` on a buffer → `OpeningMatch` | 366 |
| `classify(keys: [UInt64])` → `Opening` | 332 |

## Coverage

| | Named positions only | With transpositions (default) |
|---|---|---|
| Games with a recognized opening | 492182 (100.00 %) | 492182 (100.00 %) |
| Computed ECO = tag | 285752 (72.76 %) | 281901 (71.78 %) |
| Computed ECO ≠ tag | 106995 (27.24 %) | 110846 (28.22 %) |
| … of them with the same letter | 31350 | 33426 |
| ECO computed for games without a tag | 99435 | 99435 |

«=» and «≠» are counted over the games with a tag and a recognized opening (392747 and 392747).

### Most common disagreements (with transpositions)

| Tag → computed | Games | First example |
|---|---|---|
| A00 → D02 | 1651 | 2025: d4 d5 Bf4 e6 Nf3 Bd6 Bg3 f5 e3 Nf6 Ne5 O-O Nd2 c6 Bd3 Bc7 — «Queen's Pawn Game: London System, with e6» |
| A00 → C50 | 1587 | 2025: e4 Nc6 Nf3 e5 Bc4 Be7 c3 Nf6 d3 d5 exd5 Nxd5 Qe2 Bg4 h3 Nf4 — «Italian Game: Hungarian Defense» |
| A00 → D00 | 1313 | 2025: d4 d5 Bf4 Nc6 Nf3 Nf6 e3 Bf5 Bd3 Ne4 Bg3 e6 Nbd2 Bd6 Qe2 h6 — «Queen's Pawn Game: Accelerated London System» |
| A00 → A45 | 1159 | 2025: d4 Nf6 Bf4 d5 e3 Bf5 c4 c6 Nc3 e6 Qb3 Qb6 Nf3 Be7 h3 Ne4 — «Indian Defense: Accelerated London System» |
| A00 → B23 | 928 | 2025: e4 c5 Nc3 Nc6 Bb5 Nd4 Nf3 Nxb5 Nxb5 a6 Nc3 d6 d4 Bg4 dxc5 dxc5 — «Sicilian Defense: Closed, Traditional» |
| A00 → B22 | 904 | 2025: e4 c5 c3 d5 exd5 Qxd5 d4 cxd4 cxd4 e6 Nc3 Bb4 Nf3 Nc6 Be2 Nge7 — «Sicilian Defense: Alapin Variation, Barmen Defense» |
| A00 → B12 | 892 | 2025: e4 c6 d4 d5 e5 Bf5 Bd3 Bxd3 Qxd3 e6 Nf3 c5 dxc5 Qa5+ c3 Qxc5 — «Caro-Kann Defense: Advance Variation» |
| A00 → C54 | 877 | 2025: e4 e5 Bc4 Nc6 Nf3 Nf6 d3 Bc5 c3 d6 Nbd2 a6 Bb3 O-O h3 Ba7 — «Italian Game: Classical Variation, Giuoco Pianissimo, with a6» |
| A00 → B00 | 832 | 2025: e4 d6 d4 Nf6 Bd3 g6 f3 Nbd7 Be3 c6 c3 b5 a4 bxa4 Rxa4 Qc7 — «Pirc Defense» |
| A00 → B01 | 827 | 2025: e4 d5 exd5 Nf6 Nc3 Nxd5 Nxd5 Qxd5 Nf3 Bg4 Be2 e6 O-O Nc6 c3 O-O-O — «Scandinavian Defense: Modern Variation» |
| A00 → B13 | 822 | 2025: d4 d5 Bf4 c5 e3 cxd4 exd4 Nc6 Nf3 Bg4 Be2 Qb6 Nbd2 Nf6 Nb3 e6 — «Caro-Kann Defense: Exchange Variation» |
| A00 → C00 | 803 | 2025: e4 e6 Qe2 c5 Nc3 Nc6 Nf3 Nge7 g3 g6 Bg2 Bg7 O-O O-O d3 d5 — «French Defense: Chigorin Variation» |
| ??? → B12 | 788 | 2025: e4 c6 d4 d5 e5 Bf5 Nf3 e6 Be2 c5 Be3 cxd4 Nxd4 Ne7 c4 Nbc6 — «Caro-Kann Defense: Advance Variation, Short Variation» |
| A00 → C02 | 769 | 2025: d4 e6 e4 d5 e5 c5 c3 Nc6 Nf3 Qb6 Be2 cxd4 cxd4 Bb4+ Nc3 Nge7 — «French Defense: Advance Variation, Paulsen Attack» |
| A00 → C01 | 758 | 2025: e4 e6 d4 d5 exd5 exd5 Nc3 Bf5 Bd3 Be4 Nxe4 dxe4 Bxe4 Bb4+ c3 Qe7 — «French Defense: Exchange Variation» |
| A00 → B10 | 736 | 2025: e4 c6 b3 d5 exd5 cxd5 Bb2 Nc6 d4 Nf6 Nf3 Bg4 Be2 e6 Nbd2 Bb4 — «Caro-Kann Defense: Euwe Attack» |
| A00 → B30 | 685 | 2025: e4 c5 Nf3 Nc6 c3 b6 d4 d5 dxc5 dxe4 Qxd8+ Nxd8 Ne5 bxc5 Bb5+ Nc6 — «Sicilian Defense: Old Sicilian» |
| A00 → B90 | 682 | 2025: e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bd3 e6 O-O Be7 Bg5 Qa5 — «Sicilian Defense: Najdorf Variation, Yates Variation» |
| A00 → C44 | 657 | 2025: e4 e5 Nf3 Nc6 d4 exd4 Nxd4 Nxd4 Qxd4 d6 Bc4 Nf6 O-O Be7 Nc3 O-O — «Scotch Game: Lolli Variation» |
| A00 → A05 | 649 | 2025: Nf3 d5 g3 Nf6 Bg2 Bf5 d4 e6 O-O c6 c4 Nbd7 Nc3 Be7 Re1 O-O — «King's Indian Attack» |
| ??? → D02 | 648 | 2025: d4 d5 Nf3 Nf6 Bf4 e6 e3 c5 Nbd2 Bd6 Bb5+ Nc6 dxc5 Bxc5 c4 O-O — «Queen's Pawn Game: London System, with e6» |
| A00 → A40 | 640 | 2025: d4 g6 c4 Bg7 Nf3 c5 d5 d6 Nc3 Nf6 Bg5 Nbd7 e3 O-O Be2 a6 — «Queen's Pawn Game: Modern Defense» |
| A00 → B40 | 623 | 2025: e4 e6 d4 d5 Nf3 c5 Nc3 Nc6 Bb5 Bd7 exd5 exd5 Nxd5 Nxd4 Nxd4 cxd4 — «Sicilian Defense: Marshall Counterattack» |
| A00 → B50 | 621 | 2025: e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nc6 Nc3 a6 Be3 g6 a3 Bg7 Qd2 Nf6 — «Sicilian Defense» |
| A00 → A48 | 575 | 2025: d4 g6 Bf4 Bg7 Nf3 Nf6 e3 d6 c3 O-O Nbd2 Re8 h4 Nbd7 Ng5 Nh5 — «London System» |

### Depth of the match (with transpositions)

Average ply of the last match: 7.6.

| Ply of the match | 1–5 | 6–9 | 10–15 | 16–23 | 24–40 |
|---|---|---|---|---|---|
| Games | 172741 (35.10 %) | 178704 (36.31 %) | 121982 (24.78 %) | 18240 (3.71 %) | 515 (0.10 %) |

### A00 tags

57414 games carry `ECO "A00"`; for 54571 (95.05 %) the catalog finds another opening: the tag is a placeholder. Leaving them out (and tags that are not a valid ECO), the computed ECO equals the tag in 279058 of 309387 games (90.20 %).

### When the two modes give different ECOs

8257 games (1.68 %); the tag agrees with «named only» in 4052 and with «transpositions» in 201.

| Tag / named only / with transpositions | Games | Example |
|---|---|---|
| E10 / E10 / D30 | 470 | d4 Nf6 c4 e6 Nf3 d5 g3 dxc4 Qa4+ Nbd7 Bg2 Rb8 Qxc4 b5 Qc2 Bb7 — «Indian Defense: Anti-Nimzo-Indian» / «Queen's Gambit Declined» · E10 / E10 (ply 5) / D30 (ply 6) |
| D02 / D02 / D30 | 309 | Nf3 Nf6 d4 d5 c4 e6 g3 c6 Bg2 Bb4+ Nc3 h6 O-O O-O Ne5 Nbd7 — «Queen's Pawn Game: Symmetrical Variation» / «Queen's Gambit Declined» · D02 / D02 (ply 4) / D30 (ply 6) |
| — / E10 / D30 | 235 | d4 Nf6 Nf3 e6 c4 d5 g3 h6 Bg2 c5 O-O Be7 cxd5 exd5 Nc3 O-O — «Indian Defense: Anti-Nimzo-Indian» / «Queen's Gambit Declined» · — / E10 (ply 5) / D30 (ply 6) |
| D30 / D30 / D43 | 212 | d4 d5 c4 e6 Nf3 c6 g3 Nf6 Bg2 Bd6 O-O O-O Nc3 Nbd7 a3 a5 — «Queen's Gambit Declined» / «Semi-Slav Defense» · D30 / D30 (ply 4) / D43 (ply 6) |
| E60 / E60 / E61 | 187 | d4 Nf6 c4 g6 g3 Bg7 Bg2 O-O Nc3 d6 Nf3 Bg4 h3 Bxf3 Bxf3 c6 — «King's Indian Defense: Fianchetto Variation, Immediate Fianchetto» / «King's Indian Defense» · E60 / E60 (ply 5) / E61 (ply 11) |
| D11 / D11 / D43 | 165 | d4 d5 c4 c6 Nf3 Nf6 e3 e6 b3 Ne4 Nbd2 Nd7 Bd3 f5 Qc2 Bd6 — «Slav Defense: Quiet Variation» / «Semi-Slav Defense» · D11 / D11 (ply 7) / D43 (ply 8) |
| D02 / D02 / D10 | 126 | d4 d5 Nf3 Nf6 c4 c6 g3 e6 Bg2 Bd6 O-O Nbd7 Qc2 O-O Nc3 Re8 — «Queen's Pawn Game: Symmetrical Variation» / «Slav Defense» · D02 / D02 (ply 4) / D10 (ply 6) |
| E60 / E60 / D80 | 126 | d4 Nf6 c4 g6 g3 Bg7 Bg2 O-O Nc3 c5 d5 d6 Nf3 e6 O-O exd5 — «King's Indian Defense: Fianchetto Variation, Immediate Fianchetto» / «Grünfeld Defense» · E60 / E60 (ply 5) / D80 (ply 7) |
| D43 / D43 / D53 | 118 | d4 d5 Nf3 Nf6 c4 e6 Nc3 c6 Bg5 Be7 e3 h6 Bh4 Nbd7 Rc1 O-O — «Semi-Slav Defense» / «Queen's Gambit Declined» · D43 / D43 (ply 8) / D53 (ply 10) |
| — / D02 / D30 | 114 | Nf3 d5 d4 e6 c4 Nf6 g3 c6 Qc2 Bd6 Bg2 Nbd7 O-O O-O Rd1 Re8 — «Queen's Pawn Game: Zukertort Variation» / «Queen's Gambit Declined» · — / D02 (ply 3) / D30 (ply 6) |
| — / D30 / D43 | 95 | d4 d5 c4 e6 Nf3 c6 g3 dxc4 Bg2 b5 O-O Bb7 Ne5 Qc8 b3 cxb3 — «Queen's Gambit Declined» / «Semi-Slav Defense» · — / D30 (ply 4) / D43 (ply 6) |
| B01 / B01 / A00 | 94 | e4 d5 Nc3 Qd7 d3 Nf6 g3 h6 Bg2 g5 e5 Ng8 Nxd5 c6 Ne3 Qe6 — «Scandinavian Defense» / «Van Geet Opening» · B01 / B01 (ply 2) / A00 (ply 3) |
| D02 / D02 / D43 | 93 | d4 d5 Nf3 Nf6 c4 e6 e3 a6 b3 b6 cxd5 exd5 Bd3 Be7 O-O O-O — «Queen's Pawn Game: Symmetrical Variation» / «Semi-Slav Defense» · D02 / D02 (ply 4) / D43 (ply 7) |
| ??? / E10 / D30 | 91 | d4 Nf6 c4 e6 Nf3 d5 g3 Bb4+ Bd2 Bd6 Nc3 O-O Qc2 Nc6 Bg2 dxc4 — «Indian Defense: Anti-Nimzo-Indian» / «Queen's Gambit Declined» · ??? / E10 (ply 5) / D30 (ply 6) |
| E12 / E12 / E20 | 91 | Nf3 e6 d4 Nf6 c4 b6 Nc3 Bb4 a3 Bxc3+ bxc3 Ne4 Qc2 f5 Nd2 Bb7 — «Queen's Indian Defense: Kasparov Variation» / «Nimzo-Indian Defense» · E12 / E12 (ply 7) / E20 (ply 8) |
| A11 / A11 / A09 | 90 | c4 c6 Nf3 Nf6 Nc3 d5 e3 a6 b3 Bg4 d4 e6 Be2 Nbd7 O-O Bd6 — «English Opening: Caro-Kann Defensive System» / «Réti Opening» · A11 / A11 (ply 2) / A09 (ply 7) |
| A00 / E10 / D30 | 89 | d4 Nf6 c4 e6 Nf3 d5 g3 c5 cxd5 exd5 Bg2 Be7 O-O h6 dxc5 Bxc5 — «Indian Defense: Anti-Nimzo-Indian» / «Queen's Gambit Declined» · A00 / E10 (ply 5) / D30 (ply 6) |
| — / E60 / E61 | 87 | d4 Nf6 Nf3 g6 c4 Bg7 Nc3 O-O g3 d6 Bg2 Bd7 O-O Re8 Re1 Nc6 — «King's Indian Defense: Normal Variation, King's Knight Variation» / «King's Indian Defense» · — / E60 (ply 5) / E61 (ply 8) |
| A46 / A46 / A47 | 84 | d4 Nf6 Nf3 e6 e3 b6 Bd3 Bb7 Nbd2 d5 O-O — «Yusupov-Rubinstein System» / «Pseudo Queen's Indian Defense» · A46 / A46 (ply 5) / A47 (ply 9) |
| A46 / A46 / E14 | 81 | d4 Nf6 Nf3 e6 e3 b6 Bd3 Bb7 O-O d5 b3 Bd6 Bb2 O-O c4 Nbd7 — «Yusupov-Rubinstein System» / «Queen's Indian Defense, with e3» · A46 / A46 (ply 5) / E14 (ply 8) |

### Games without a recognized opening (sample)

