<p align="center">
  <img src="Resources/Logo.png" width="420" alt="맥코디언 (Maccordion) 로고">
</p>

<h1 align="center">맥코디언 (Maccordion)</h1>

<p align="center">맥북 뚜껑을 아코디언 바람통처럼 여닫아 연주하는 macOS 악기 앱</p>

---

## 어떻게 연주하나요?

맥북 화면(뚜껑)이 아코디언의 **바람통**, 키보드가 **건반**이에요.
건반을 누른 채로 뚜껑을 여닫으면 소리가 나요. 빨리 움직일수록 소리가 커지고, 멈추면 소리도 멈춰요.

```
   윗줄    W E   T Y U   O P          ← 검은 건반
 가운데줄  A S D F G H J K L ; '       ← 흰 건반 (C4 ~ F5)
   아랫줄  Z X C V B N                ← 왼손 화음 C · F · G · Am · Dm · Em
```

| 키 | 기능 |
|---|---|
| `↑` `↓` | 멜로디 옥타브 올리기 / 내리기 |
| `Tab` | 아코디언 모드 ↔ 테레민 모드 |

키는 물리적 위치로 인식하므로 한글 자판 상태에서도 그대로 연주할 수 있어요.

### 테레민 모드
뚜껑 **각도**가 음높이(30°~130° = C4~C6)가 되고, 트랙패드를 누르는 세기(또는 스페이스바)가 음량이 돼요.

## 요구 사항

- macOS 14 (Sonoma) 이상
- 뚜껑 각도 센서가 있는 Apple Silicon 맥북 (MacBook Air M3에서 확인)

## 빌드

Xcode 없이 Command Line Tools만으로 빌드해요.

```sh
./build.sh run      # 빌드 후 실행 (build/Maccordion.app)
./build.sh test     # 자체 테스트
./build.sh angle    # 뚜껑 각도 실시간 확인
./build.sh logo     # 로고/앱 아이콘 다시 만들기
```

## 문서

- [SPEC.md](SPEC.md) — 제품 명세서
