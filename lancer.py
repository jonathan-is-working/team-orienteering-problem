#!/usr/bin/env python3
"""Simple menu to run the project without typing Julia commands.

Usage: python3 lancer.py   (on Windows: python lancer.py)
Requires Julia on the PATH and Python 3.8 or newer (standard library only).
"""
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPORT = ROOT / "docs" / "Rapport_TOP_AI09_RO06_LE-Jonathan_CARON-Maxence.pdf"


def julia_install_help():
    system = platform.system()
    print("Julia est introuvable. Installez-le, puis relancez ce script dans un nouveau terminal.")
    if system == "Windows":
        print("  winget install --name Julia --id 9NJNWW8PVKMN -e -s msstore")
    else:
        print("  curl -fsSL https://install.julialang.org | sh")
    print("Détails : https://julialang.org/downloads/")


def julia(*args):
    """Run `julia --project=. ARGS...` from the repository root and stream its output."""
    command = ["julia", "--project=.", *args]
    print("\n$ " + " ".join(command) + "\n")
    try:
        return subprocess.run(command, cwd=ROOT).returncode == 0
    except KeyboardInterrupt:
        print("\nInterrompu.")
        return False


def ask(prompt, default=""):
    suffix = f" [{default}]" if default else ""
    answer = input(f"{prompt}{suffix} : ").strip()
    return answer or default


def confirm(prompt):
    return ask(prompt + " (o/n)", "n").lower() in ("o", "oui", "y", "yes")


def solve_instance():
    print("\nLes instances vont de p1 à p7 (19 à 100 clients), par exemple p2.3.h, p4.2.j ou p7.4.t.")
    name = ask("Instance", "p2.3.h")
    if not (ROOT / "data" / "benchmarks" / "chao" / f"{name}.txt").is_file():
        print(f"Instance {name} introuvable dans data/benchmarks/chao.")
        return
    print("  1. Toutes les méthodes\n  2. Algo 1\n  3. Algo 2\n  4. PLNE")
    method = {"1": "all", "2": "algo1", "3": "algo2", "4": "milp"}.get(ask("Méthode", "1"), "all")
    args = ["scripts/solve.jl", name, method]
    if method in ("all", "milp"):
        args.append(ask("Limite de temps de la PLNE en secondes", "60"))
    julia(*args)


def rerun_heuristics():
    print("\nRelance l'Algo 1, l'Algo 2 et le contrôle sur les 353 instances (environ 10 minutes),")
    print("puis régénère les tableaux. Les résultats actuels de results/raw/ seront remplacés.")
    if confirm("Continuer ?"):
        julia("scripts/benchmark.jl", "chao") and julia("scripts/analyze.jl")


def rerun_milp():
    print("\nRelance la PLNE sur p2, p1 et p3, 60 s au plus par instance (environ 1 h 45),")
    print("puis régénère les tableaux. Les nouveaux résultats remplacent les nôtres.")
    if not confirm("Continuer ?"):
        return
    for family in ("p2", "p1", "p3"):
        if not julia("scripts/benchmark.jl", "milp", family):
            return
    julia("scripts/analyze.jl")


def open_report():
    system = platform.system()
    if system == "Windows":
        os.startfile(REPORT)  # Windows only
    else:
        subprocess.run(["open" if system == "Darwin" else "xdg-open", str(REPORT)])


MENU = [
    ("Résoudre une instance (Algo 1, Algo 2, PLNE)", solve_instance),
    ("Lancer les tests", lambda: julia("test/runtests.jl")),
    ("Recalculer les résultats des heuristiques (~10 min)", rerun_heuristics),
    ("Recalculer les résultats de la PLNE (~1 h 45)", rerun_milp),
    ("Régénérer les tableaux et figures du rapport", lambda: julia("scripts/analyze.jl")),
    ("Ouvrir le rapport (PDF)", open_report),
]


def main():
    sys.stdout.reconfigure(line_buffering=True)  # keep our messages in order with Julia's output
    if shutil.which("julia") is None:
        julia_install_help()
        sys.exit(1)
    print("Installation des dépendances Julia (rapide si déjà faite)...")
    if not julia("-e", "using Pkg; Pkg.instantiate()"):
        sys.exit(1)
    while True:
        print("\n=== Team Orienteering Problem - AI09 / RO06 ===")
        for number, (label, _) in enumerate(MENU, start=1):
            print(f"  {number}. {label}")
        print("  0. Quitter")
        try:
            choice = ask("Choix", "1")
        except (KeyboardInterrupt, EOFError):
            print()
            break
        if choice == "0":
            break
        if choice.isdigit() and 1 <= int(choice) <= len(MENU):
            MENU[int(choice) - 1][1]()
        else:
            print("Choix invalide.")


if __name__ == "__main__":
    main()
