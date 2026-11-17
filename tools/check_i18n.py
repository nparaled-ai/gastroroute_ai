#!/usr/bin/env python3
"""
Comprueba las traducciones de la app: que ningun texto se quede en pantalla como una clave
cruda ("planner.lunch_kind_cafe"). Se ejecuta desde la raiz del proyecto Flutter:

    python tools/check_i18n.py

Sale con codigo 1 si hay algun problema. Comprueba:

  1. Paridad: los 6 idiomas (es, en, fr, de, it, pt) tienen EXACTAMENTE las mismas claves.
  2. Claves escritas enteras en el codigo ('catalog.title'.tr()): existen en es.
     Una clave con plural (one/other) o con subclaves cuenta como existente.
  3. Claves construidas por trozos ('assistant.lunch_kind_$k'): se COMPRUEBAN SOLO las que estan
     declaradas en DINAMICAS con todos los valores que puede tomar la variable. Una clave
     interpolada que no este declarada se avisa: quien la añada tiene que declarar sus valores
     aqui, que es lo que habria evitado el fallo del 17-11-2026 (se buscaba en `planner.` una
     clave que vivia en `assistant.`).
"""
import glob
import json
import re
import sys

IDIOMAS = ['es', 'en', 'fr', 'de', 'it', 'pt']

# Claves interpoladas: patron tal como aparece en el codigo -> valores que puede tomar.
# Las que estan en None son anteriores al catalogo y NO se han revisado una a una: se comprueba
# solo que el patron case con alguna clave de es.json (aviso, no error).
DINAMICAS = {
    # Rutas moteras (13-17 nov 2026), revisadas una a una
    'catalog.entry_$e': ['catalog.entry_nearest', 'catalog.entry_start', 'catalog.entry_end'],
    'catalog.part_${p[': ['catalog.part_approach', 'catalog.part_route', 'catalog.part_return'],
    'catalog.mod_season_$t': ['catalog.mod_season_unknown', 'catalog.mod_season_todo_el_ano', 'catalog.mod_season_cerrado_invierno', 'catalog.mod_season_ocasional'],
    'assistant.lunch_kind_$k': ['assistant.lunch_kind_almuerzo', 'assistant.lunch_kind_cafe'],
    'assistant.lunch_kind_$clase': ['assistant.lunch_kind_almuerzo', 'assistant.lunch_kind_cafe'],
}


def a_regex(patron):
    """Convierte 'assistant.lunch_kind_$k' o "catalog.part_${p[" en una expresion que case con
    todas las claves posibles: cada $variable o ${...} pasa a ser «cualquier cosa»."""
    marcador = '@@MARCA@@'
    sin = re.sub(r'\$\{[^}]*\}?|\$[A-Za-z_0-9]+', marcador, patron)
    return re.compile('^' + re.escape(sin).replace(re.escape(marcador), '.+') + '$')


def plano(d, p=''):
    out = {}
    for k, v in d.items():
        kk = p + k
        if isinstance(v, dict):
            out[kk] = v          # el propio nodo cuenta como existente (plurales, secciones)
            out.update(plano(v, kk + '.'))
        else:
            out[kk] = v
    return out


def main():
    raiz = 'assets/translations'
    D = {l: json.load(open('%s/%s.json' % (raiz, l), encoding='utf-8')) for l in IDIOMAS}
    F = {l: plano(D[l]) for l in IDIOMAS}
    errores = []
    avisos = []

    # 1) paridad
    for l in IDIOMAS[1:]:
        for k in F['es']:
            if k not in F[l]:
                errores.append('[%s] falta la clave %s' % (l, k))
        for k in F[l]:
            if k not in F['es']:
                errores.append('[%s] sobra la clave %s (no esta en es)' % (l, k))

    secciones = sorted({k.split('.')[0] for k in F['es']})
    alt = '|'.join(re.escape(s) for s in secciones)
    literal = re.compile(r"'((?:%s)\.[A-Za-z_0-9]+)'" % alt)
    interpolada = re.compile(r"'((?:%s)\.[A-Za-z_0-9]*\$[^']*)'" % alt)

    vistas = set()
    for f in sorted(glob.glob('lib/**/*.dart', recursive=True)):
        s = open(f, encoding='utf-8').read()
        corto = f.replace('\\', '/')

        # 2) literales
        for m in literal.finditer(s):
            k = m.group(1)
            if '$' in k:
                continue
            if k not in F['es']:
                # puede ser una clave que se pasa a una funcion y no una de traduccion: solo es
                # error si el codigo la traduce
                trozo = s[m.end():m.end() + 12]
                if re.match(r"\s*\.\s*(tr|plural)\s*\(", trozo):
                    errores.append('%s: la clave %s no existe' % (corto, k))

        # 3) interpoladas
        for m in interpolada.finditer(s):
            patron = m.group(1)
            if patron in vistas:
                continue
            vistas.add(patron)
            if patron in DINAMICAS and DINAMICAS[patron]:
                for k in DINAMICAS[patron]:
                    for l in IDIOMAS:
                        if k not in F[l]:
                            errores.append('%s: %s -> falta %s en [%s]' % (corto, patron, k, l))
            elif patron in DINAMICAS:
                regex = a_regex(patron)
                if not any(regex.match(k) for k in F['es']):
                    avisos.append('%s: %s no casa con ninguna clave' % (corto, patron))
            else:
                # Sin declarar: al menos se exige que el patron case con alguna clave real (si no,
                # es un error seguro); y se avisa para que se declaren sus valores.
                regex = a_regex(patron)
                casan = [k for k in F['es'] if regex.match(k)]
                if not casan:
                    errores.append('%s: la clave interpolada %s no casa con ninguna clave de es' % (corto, patron))
                else:
                    avisos.append('%s: %s (casa con %d claves; sin declarar sus valores)' % (corto, patron, len(casan)))

    for a in avisos:
        print('AVISO  ' + a)
    for e in errores:
        print('ERROR  ' + e)
    print('\n%d idiomas · %d claves en es · %d errores · %d avisos' % (len(IDIOMAS), len(F['es']), len(errores), len(avisos)))
    return 1 if errores else 0


if __name__ == '__main__':
    sys.exit(main())
