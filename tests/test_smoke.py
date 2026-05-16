"""Smoke test ensuring the test runner has at least one test to collect."""


def test_package_importable() -> None:
    import scripts

    assert scripts is not None
