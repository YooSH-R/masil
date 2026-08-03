"""pytest가 프로젝트 루트를 sys.path에 넣게 하기 위한 파일.

이 파일이 없으면 tests/ 안에서 `import walklog` 이 ModuleNotFoundError로 실패한다.
내용은 비어 있어도 되며, 존재 자체가 목적이다.
"""