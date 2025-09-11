#!/bin/bash

# Cicla su tutte le directory nella directory corrente
for dir in */; do
  # Rimuove il trailing slash
  dir=${dir%/}

  # Crea il nuovo nome della directory rimuovendo spazi e caratteri speciali
  new_name=$(echo "$dir" | tr -s ' ' '-' | sed 's/[^a-zA-Z0-9_-]//g')

  # Se il nuovo nome è diverso dal nome originale, rinomina la directory
  if [[ "$dir" != "$new_name" ]]; then
    mv -v -- "$dir" "$new_name"
  fi
done
