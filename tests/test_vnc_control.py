"""vnc_control.py: validation, token files and the viewer list, against temporary directories."""
import importlib.util, json, os, sys, tempfile, pathlib
import pytest

HERE = pathlib.Path(__file__).resolve().parent


@pytest.fixture()
def vc(tmp_path, monkeypatch):
    (tmp_path / "tokens").mkdir(); (tmp_path / "web").mkdir()
    cfg = tmp_path / "config.json"
    cfg.write_text(json.dumps({"token": "t", "tokens_dir": str(tmp_path / "tokens"), "web_dir": str(tmp_path / "web")}))
    monkeypatch.setenv("VNC_CONTROL_CONFIG", str(cfg))
    spec = importlib.util.spec_from_file_location("vnc_control", HERE.parent / "linux" / "vnc_control.py")
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    return mod, tmp_path


def test_validate(vc):
    m, _ = vc
    s = m.validate({"name": "Office PC", "host": "192.168.1.20", "port": "5901", "password": "pw"})
    assert s["token"] == "office-pc" and s["port"] == 5901 and (s["width"], s["height"]) == (1024, 600)
    assert m.validate({"name": "nas", "host": "nas.local"})["port"] == 5900
    for bad in ({"name": "", "host": "1.2.3.4"}, {"name": "x", "host": "bad host"}, {"name": "x", "host": "1.2.3.4", "port": 70000},
                {"name": "x;rm", "host": "1.2.3.4"}, {"name": "x", "host": "1.2.3.4", "width": 5}):
        with pytest.raises(ValueError):
            m.validate(bad)


def test_save_writes_tokens_and_public_list(vc):
    m, d = vc
    m.save([m.validate({"name": "Pi", "host": "127.0.0.1"}), m.validate({"name": "Office PC", "host": "10.0.0.5", "port": 5901})])
    assert (d / "tokens" / "office-pc").read_text() == "office-pc: 10.0.0.5:5901\n"
    pub = json.loads((d / "web" / "vnc-sessions.json").read_text())
    assert [p["token"] for p in pub] == ["pi", "office-pc"] and "host" not in pub[0]
    m.save([s for s in m.load() if s["token"] != "pi"])  # removing a session removes its token file
    assert sorted(os.listdir(d / "tokens")) == ["office-pc"]
