"""
Optimiza las imágenes de la app (restaurantes y productos) para bajar el peso del APK.

Qué hace:
  1. Convierte PNG/JPG a WebP y reduce las que son muy grandes
       - restaurantes: máximo 1280 px de ancho
       - productos:    máximo  800 px de ancho
  2. Renombra cada archivo como lo busca la app (minúsculas, sin acentos,
     guiones en lugar de espacios): "Volcán de Bistec.PNG" -> "volcan-de-bistec.webp"
  3. Guarda los originales en  imagenes_originales/  (en la raíz del repo, NO se sube a GitHub)
  4. Compara con backend/app/datos_demo.py y avisa qué imágenes FALTAN y cuáles SOBRAN
  5. Crea copias de respaldo para las fachadas que falten (solo si no existen)

Uso (desde la raíz del repo, en Git Bash):
    pip install pillow
    python herramientas/optimizar_imagenes.py --revisar     # solo muestra, no cambia nada
    python herramientas/optimizar_imagenes.py               # optimiza de verdad

Se puede correr varias veces sin problema.
"""

import importlib.util
import shutil
import sys
from pathlib import Path

from PIL import Image

RAIZ = Path(__file__).resolve().parent.parent
BASE = RAIZ / "app" / "assets" / "images"
ORIGINALES = RAIZ / "imagenes_originales"
DATOS_DEMO = RAIZ / "backend" / "app" / "datos_demo.py"

ANCHO_MAXIMO = {"restaurantes": 1280, "productos": 800}
CALIDAD_WEBP = 78
EXTENSIONES = {".png", ".jpg", ".jpeg", ".webp"}
# Un .webp con el nombre correcto, que no pase del ancho máximo y pese menos que
# esto, ya está optimizado y no se vuelve a tocar (así se puede correr varias veces).
WEBP_YA_OPTIMO_KB = {"restaurantes": 600, "productos": 350}

# Fachada que falta -> fachada que se copia en su lugar (solo si no existe la suya).
COPIAS = {
    "hamburguesas-suspiro": "hamburguesas-beto",
    "hermanos-burger": "hamburguesas-beto",
    "angelo-s-pizza": "hermano-s-pizza",
    "pizzas-don-george": "hermano-s-pizza",
    "cafe-moustach": "arte-latte",
    "pasteles-ammmbigu": "pasteleria-el-mana",
    "la-cruderia": "restaurante-el-sazon",
    "samba-da-brasa-churrasca": "restaurante-el-sazon",
    "pizza-express": "hermano-s-pizza",
    "hamburguesas-el-buen-sabor": "hamburguesas-beto",
}


def slug(texto: str) -> str:
    """Misma regla que Imagenes.slug() de la app (lib/core/imagenes.dart)."""
    t = texto.lower()
    for a, b in zip("áéíóúüñ", "aeiouun"):
        t = t.replace(a, b)
    salida = []
    for c in t:
        salida.append(c if ("a" <= c <= "z" or "0" <= c <= "9") else "-")
    t = "".join(salida)
    while "--" in t:
        t = t.replace("--", "-")
    return t.strip("-")


def kb(ruta: Path) -> float:
    return ruta.stat().st_size / 1024


def cargar_datos_demo():
    if not DATOS_DEMO.exists():
        return None
    spec = importlib.util.spec_from_file_location("datos_demo", DATOS_DEMO)
    modulo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modulo)
    return modulo


def a_rgb(img: Image.Image) -> Image.Image:
    """Quita la transparencia sobre blanco (las fotos no la necesitan)."""
    if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
        img = img.convert("RGBA")
        fondo = Image.new("RGB", img.size, (255, 255, 255))
        fondo.paste(img, mask=img.split()[-1])
        return fondo
    return img.convert("RGB")


def optimizar_carpeta(nombre: str, solo_revisar: bool) -> tuple[float, float, int]:
    carpeta = BASE / nombre
    if not carpeta.exists():
        print(f"\n[{nombre}] la carpeta {carpeta} no existe. Se omite.")
        return 0.0, 0.0, 0

    ancho_max = ANCHO_MAXIMO[nombre]
    destino_orig = ORIGINALES / nombre
    archivos = sorted(
        p for p in carpeta.iterdir() if p.is_file() and p.suffix.lower() in EXTENSIONES
    )
    print(f"\n=== {nombre}: {len(archivos)} imágenes (ancho máximo {ancho_max} px) ===")

    antes = despues = 0.0
    procesadas = 0
    vistos: dict[str, str] = {}

    for origen in archivos:
        nuevo_nombre = slug(origen.stem) + ".webp"
        destino = carpeta / nuevo_nombre
        peso_antes = kb(origen)

        if nuevo_nombre in vistos and vistos[nuevo_nombre] != origen.name:
            print(f"  AVISO: {origen.name} y {vistos[nuevo_nombre]} dan el mismo nombre ({nuevo_nombre}). Revísalas.")
        vistos[nuevo_nombre] = origen.name

        with Image.open(origen) as img:
            ancho, alto = img.size
            ya_optima = (
                origen.suffix.lower() == ".webp"
                and origen.name == nuevo_nombre
                and ancho <= ancho_max
                and peso_antes <= WEBP_YA_OPTIMO_KB[nombre]
            )
            if ya_optima:
                antes += peso_antes
                despues += peso_antes
                continue

            if solo_revisar:
                print(f"  {origen.name}  {peso_antes:7.0f} KB  {ancho}x{alto}  ->  {nuevo_nombre}")
                antes += peso_antes
                despues += peso_antes
                procesadas += 1
                continue

            imagen = a_rgb(img)
            if ancho > ancho_max:
                alto = round(alto * ancho_max / ancho)
                imagen = imagen.resize((ancho_max, alto), Image.LANCZOS)

            # Respaldo del original antes de tocar nada.
            destino_orig.mkdir(parents=True, exist_ok=True)
            respaldo = destino_orig / origen.name
            n = 1
            while respaldo.exists():
                respaldo = destino_orig / f"{origen.stem}_{n}{origen.suffix}"
                n += 1
            shutil.copy2(origen, respaldo)

            imagen.save(destino, "WEBP", quality=CALIDAD_WEBP, method=6)
            if origen.resolve() != destino.resolve():
                origen.unlink()

        peso_despues = kb(destino)
        antes += peso_antes
        despues += peso_despues
        procesadas += 1
        print(f"  {origen.name:45s} {peso_antes:7.0f} KB -> {peso_despues:5.0f} KB  ({nuevo_nombre})")

    return antes, despues, procesadas


def crear_copias_de_fachadas(solo_revisar: bool):
    carpeta = BASE / "restaurantes"
    if not carpeta.exists():
        return
    extensiones = (".webp", ".png", ".jpg", ".jpeg")

    def existe(nombre):
        return any((carpeta / f"{nombre}{e}").exists() for e in extensiones)

    print("\n=== Fachadas de respaldo ===")
    hubo = False
    for faltante, modelo in COPIAS.items():
        if existe(faltante) or not existe(modelo):
            continue
        hubo = True
        if solo_revisar:
            print(f"  faltaría: {faltante}  (se copiaría de {modelo})")
        else:
            shutil.copy2(carpeta / f"{modelo}.webp", carpeta / f"{faltante}.webp")
            print(f"  copia creada: {faltante}.webp  (de {modelo}.webp)")
    if not hubo:
        print("  Ninguna: todas las fachadas ya tienen su imagen.")


def comparar_con_datos(solo_revisar: bool):
    datos = cargar_datos_demo()
    if datos is None:
        print("\n(No se encontró backend/app/datos_demo.py; se omite la comparación.)")
        return

    def existentes(nombre):
        carpeta = BASE / nombre
        if not carpeta.exists():
            return set()
        return {slug(p.stem) for p in carpeta.iterdir() if p.suffix.lower() in EXTENSIONES}

    # --- fachadas
    esperadas_r = {slug(r["nombre"]) for r in datos.RESTAURANTES}
    esperadas_r |= {slug(n) for n in getattr(datos, "RESTAURANTES_ANTERIORES", [])[:2]}
    hay_r = existentes("restaurantes")
    faltan_r = sorted(esperadas_r - hay_r)
    print("\n=== Revisión de fachadas ===")
    print(f"  Con imagen: {len(esperadas_r & hay_r)} de {len(esperadas_r)}")
    for f in faltan_r:
        print(f"  FALTA: {f}")

    # --- productos
    esperados_p = {}
    for r in datos.RESTAURANTES:
        for prod in r["productos"]:
            esperados_p.setdefault(slug(prod[0]), []).append(r["nombre"])
    hay_p = existentes("productos")
    faltan_p = sorted(set(esperados_p) - hay_p)
    sobran_p = sorted(hay_p - set(esperados_p))
    print("\n=== Revisión de productos ===")
    print(f"  Con imagen: {len(set(esperados_p) & hay_p)} de {len(esperados_p)} productos distintos")
    for f in faltan_p:
        print(f"  FALTA: {f}.webp   ({', '.join(sorted(set(esperados_p[f])))})")
    if sobran_p:
        print("\n  Imágenes que NO coinciden con ningún producto de datos_demo.py")
        print("  (pueden ser de Pizza Express / El Buen Sabor, o tener el nombre mal):")
        for f in sobran_p:
            print(f"  SOBRA: {f}")


def main():
    solo_revisar = "--revisar" in sys.argv
    print("MODO REVISIÓN: no se cambia ningún archivo." if solo_revisar else "OPTIMIZANDO imágenes...")

    total_antes = total_despues = 0.0
    for carpeta in ("restaurantes", "productos"):
        a, d, _ = optimizar_carpeta(carpeta, solo_revisar)
        total_antes += a
        total_despues += d

    crear_copias_de_fachadas(solo_revisar)
    comparar_con_datos(solo_revisar)

    print("\n=== Resumen ===")
    if solo_revisar:
        print(f"  Peso actual de las imágenes: {total_antes / 1024:.1f} MB")
    else:
        ahorro = total_antes - total_despues
        print(f"  Antes:   {total_antes / 1024:.1f} MB")
        print(f"  Después: {total_despues / 1024:.1f} MB")
        print(f"  Ahorro:  {ahorro / 1024:.1f} MB")
        print(f"  Originales guardados en: {ORIGINALES}")


if __name__ == "__main__":
    main()
