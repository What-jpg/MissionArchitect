# NASA data used in Mission Architect

| What | Where in the game | Source |
|---|---|---|
| LRO LROC colour mosaic of the Moon (CGI Moon Kit) | Moon sprite: mission map, hub sky, transfer, title of landing scenes (`assets/art/moon.png`) | https://svs.gsfc.nasa.gov/4720 |
| Blue Marble flat Earth map | Earth sprite: mission map, orbit screen, lunar sky (`assets/art/earth.png`) | https://svs.gsfc.nasa.gov/3615 |
| NASA Moon Fact Sheet (radius, surface gravity 1.62 m/s², escape velocity, distance, orbital period) | Lander gravity (1.62 m/s²), guide section “Real NASA data” | https://nssdc.gsfc.nasa.gov/planetary/factsheet/moonfact.html |
| Apollo 11 landing site (0.67° N, 23.47° E) | Sea of Tranquility mission brief | https://www.nasa.gov/mission/apollo-11/ |
| Apollo 16 landing site, Descartes Highlands (8.97° S, 15.50° E) | Lunar Highlands mission brief | https://www.nasa.gov/mission/apollo-16/ |
| LCROSS / LRO water-ice findings at the lunar south pole (Shackleton crater) | South Pole mission brief, ice detector | https://science.nasa.gov/mission/lcross/ |

Sprites are regenerated with `tools/make_planets.py <moon_map> <earth_map>` (orthographic projection,
pixelated to 64 px and scaled ×3). NASA imagery is public domain.
