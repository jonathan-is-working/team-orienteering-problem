# Provenance des données

## Instances

Les 387 fichiers `.txt` sont les instances de Chao, Golden et Wasil, *The team orienteering problem*, European Journal of Operational Research 88(3), 1996, DOI [10.1016/0377-2217(94)00289-4](https://doi.org/10.1016/0377-2217(94)00289-4).

Ils sont repris sans modification de l'archive publique [`chao.zip`](https://www.hds.utc.fr/~moukrim/dokuwiki/_media/en/chao.zip) de la [page TOP d'Aziz Moukrim (UTC)](https://www.hds.utc.fr/~moukrim/dokuwiki/en/top), téléchargée le 18 novembre 2026. `provenance.json` donne l'empreinte SHA-256 de l'archive et de chaque fichier.

Format ([description officielle](https://www.hds.utc.fr/~moukrim/dokuwiki/_media/en/format-top-instance.txt)) : trois lignes d'en-tête `n;…`, `m;…`, `tmax;…`, puis `n` lignes `x;y;profit`. La première ligne est le départ, la dernière l'arrivée. Les temps de trajet sont les distances euclidiennes, calculées sans arrondi.

## Meilleures solutions connues (`bks.csv`)

`bks.csv` reprend la colonne *BEST* du fichier `results/results.xls` de l'archive [`hb_web_top.zip`](https://www.hds.utc.fr/~moukrim/dokuwiki/_media/en/hb_web_top.zip), publiée avec Bouly, Dang et Moukrim, *A memetic algorithm for the team orienteering problem*, 4OR 8(1), 2010.

Pour 7 instances (p1.3.h, p1.3.o, p2.3.h, p3.4.k, p5.3.e, p6.4.j, p6.4.k), cette colonne est vide. Nous reprenons alors la solution entière de Boussier, Feillet et Gendreau donnée dans le fichier `errors/extractErr.csv` de la même archive.

Ces valeurs sont des meilleures solutions connues, pas des optima prouvés. Les 34 instances de BKS nulle (aucun client atteignable) sont exclues des expériences.

Aucune licence n'est indiquée pour ces données. Elles restent la propriété de leurs auteurs et ne sont pas couvertes par la licence du code.
