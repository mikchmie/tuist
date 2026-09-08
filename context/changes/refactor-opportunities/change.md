---
change_id: refactor-opportunities
title: Turn test-service tech debt findings into ranked refactor opportunities
status: plan_reviewed
created: 2026-09-08
updated: 2026-09-08
archived_at: null
---

## Notes

Intencja: mamy analizę modułu, która dokumentuje dług techniczny
i ryzyka strukturalne: context/changes/test-service-analysis/research.md. Ta zmiana odpowiada na pytanie, które tamta analiza celowo zostawiła otwarte:
KTÓRE z tych problemów warto naprawić, w jakim docelowym kształcie i w jakiej kolejności. Eksplorujemy każdy zapisany problem w kodzie i historii, a potem porządkujemy jako refactor opportunities.
Zmiana przebiega etapami: eksploracja → decyzja i plan → implementacja. Na etapie eksploracji nie dzieje się żaden refaktor i nie zapada żadna decyzja.
Wynik eksploracji: research.md tej zmiany, zakończony rankingiem opcji z trade-offami. Najpierw przeczytam raport; decyzja, co realizujemy, zapada na etapie planowania, a refaktor rusza dopiero według przyjętego planu.
