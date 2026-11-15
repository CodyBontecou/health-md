"""Isolated mutation inputs for a manifest's bounded localization boundary.

Production-catalog assertions keep their complete loaded catalog. Mutations need
every locale/variation of the owned keys and display dependencies, not copies of
unrelated app strings on every iteration.
"""
from copy import deepcopy


def mutation_inputs(catalog: dict, manifest: dict, sources: dict) -> tuple:
    keys = set(manifest["keys"]) | set(manifest.get("displayDependencies", []))
    strings = catalog["strings"]
    scoped = {**catalog, "strings": {key: strings[key] for key in keys if key in strings}}
    return deepcopy(scoped), deepcopy(manifest), dict(sources)
