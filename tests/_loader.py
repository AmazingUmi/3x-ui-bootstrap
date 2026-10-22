"""Load the exact embedded Python without invoking the install entry point."""
from pathlib import Path
import types

ROOT = Path(__file__).resolve().parents[1]


def load_installer():
    path = ROOT / "install-3x-ui.sh"
    source = path.read_text().split("<<'PYTHON'\n", 1)[1].rsplit("\nPYTHON", 1)[0]
    module = types.ModuleType("bootstrap_under_test")
    module.__file__ = str(path)
    exec(compile(source, str(path) + ":embedded-python", "exec"), module.__dict__)
    return module
