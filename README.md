# Col
보디빌딩

# 보디빌딩Pro — iPhone 네이티브 개발본 0.2

SwiftUI로 만든 실제 iOS 앱 프로젝트입니다. WebView·Safari·PWA를 사용하지 않습니다.
**이 파일은 소스 프로젝트이며 설치 파일(IPA)이 아닙니다. 현재 환경에 Mac/Xcode가 없어 Swift 컴파일·실기기 검증·서명을 아직 수행하지 못했습니다.**

## 이번 변경

- 밝은 흰색/녹색, 첫 화면 2열 6개 메뉴. 일반 화면 크기는 스크롤 없이, 접근성 큰 글씨/매우 작은 화면은 스크롤로 메뉴 접근 보장.
- 운동 이어하기, 지난 운동 복제, 벤치·스쿼트·데드·오버헤드 바로 시작, 이전 수행 기록 표시.
- 세트 중량·횟수 유효 입력 자동 저장, 완료 시 휴식 시작, 목록 시트 삭제 및 세트 삭제 버튼.
- 식단: 아침·점심·저녁, 10종 기본 식품 참고값과 수기 음식, 최근 먹은 음식/섭취량 다시 선택.
- iOS 로컬 알림: 타이머 종료 및 식단 알림. 잠금·무음·집중 모드는 실기기 검증 필요.
- 개인 사진/동영상 촬영·가져오기·보관함·대표사진·D-day·증량 일기.
- 기기 내 자동 저장. 전체 기록과 연결 미디어를 `.bbpro` 패키지로 내보내고 복원하는 코드 추가(256MB 한도).
- 복원은 명시적 확인 후 현재 기록 교체. 손상/누락 파일은 교체 전에 거절. 복원 미디어는 새 파일명으로 먼저 저장하고, 기록 저장 성공 후 이전 파일 정리. 식단 알림은 복원 후 다시 켜기.

## 아직 연결되지 않은 기능

계정 로그인/클라우드 동기화, 웹 테스트판 기록 가져오기, 네이티브 커뮤니티/운영자 서버, 고객 문의, 결제/구독/배지.
기존 웹 서비스와 이 앱의 데이터는 자동으로 연결되지 않습니다. 커뮤니티 메뉴에는 연결 준비 중이라고 표시합니다.
앱 종료 후 기기 내 기록은 남지만, 앱 삭제 시 백업하지 않은 기록은 사라질 수 있습니다.

## Mac에서 실행

1. Xcode 설치 후 `BodybuildingPro.xcodeproj`를 엽니다. iOS 17 이상 대상입니다.
2. Terminal에서 `bash scripts/check-ios.sh`를 실행합니다. 모델 검사와 서명 없는 시뮬레이터 빌드를 진행합니다. **실행 결과는 아직 없음**.
3. Xcode에서 시뮬레이터를 선택하고 실행, `docs/VALIDATION.md`의 동작을 확인합니다.
4. 실제 아이폰은 Signing & Capabilities에서 본인 Team을 선택하고, `com.example.bodybuildingpro`를 본인의 고유 식별자로 변경합니다. 아이폰 연결 및 필요한 Developer Mode 설정 후 Run.
5. TestFlight 배포는 Apple Developer Program, App Store Connect 앱 등록, 서명된 Archive 및 업로드가 추가로 필요합니다. Apple 계정 암호나 인증코드를 소스/채팅에 넣지 마세요.

`.github/workflows/ios-build.yml`은 Mac 빌드 검사용 구성입니다. GitHub 저장소에 올려 실행하기 전까지 실제 실행된 것이 아닙니다. 시뮬레이터 빌드는 아이폰에 설치할 수 있는 IPA가 아닙니다.

프로젝트 재생성: `python3 generate_project.py`. 외부 Swift 패키지 의존성 없음.

## Apple 안내

- 실행/서명: https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices
- TestFlight: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/

실제 계정 연결과 서버 보안은 웹 테스트판 세션을 앱에 그대로 복사하는 방식으로 해결하지 않습니다. 네이티브 인증을 갖춘 서버가 필요합니다. 과거 기획 문서는 요구사항 이력이며 구현 완료 증거가 아닙니다.
