#Requires -Version 5.1

# ============================================================
# SD 출력 폴더(Output) 정리 스크립트
# ============================================================

# ------------------------------------------------------------
# 1. 관리자 권한 확인 및 UAC 승격
# ------------------------------------------------------------
$currentIdentity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
$isAdministrator  = $currentPrincipal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdministrator) {
    Write-Host "관리자 권한이 필요합니다. UAC 권한 상승을 요청합니다..." -ForegroundColor Yellow

    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""

    Start-Process `
        -FilePath "powershell.exe" `
        -Verb RunAs `
        -ArgumentList $arguments

    exit
}


# ------------------------------------------------------------
# 2. 설정 파일 저장 경로
# ------------------------------------------------------------
$configPath = Join-Path $env:APPDATA "SD_Cleaner_Config.xml"


# ------------------------------------------------------------
# 3. SD 경로 설정 함수
# ------------------------------------------------------------
function Set-SDPath {

    Write-Host ""
    Write-Host "[초기 설정 및 경로 변경]" -ForegroundColor Cyan

    # 드라이브 문자 입력
    while ($true) {

        $script:Drive = Read-Host "드라이브 문자를 입력하세요 (예: C, D)"

        # 공백 제거
        $script:Drive = $script:Drive.Trim()

        # C: 형태로 입력한 경우 : 제거
        $script:Drive = $script:Drive -replace ':$', ''

        if ($script:Drive -match '^[A-Za-z]$') {
            $script:Drive = $script:Drive.ToUpper()
            break
        }

        Write-Host "올바른 드라이브 문자를 입력해주세요. 예: C 또는 D" -ForegroundColor Red
    }


    # 하위 경로 입력
    while ($true) {

        $script:SubPath = Read-Host "드라이브 문자를 제외한 하위 폴더 경로를 입력하세요 (예: AI\stable-diffusion-webui)"

        $script:SubPath = $script:SubPath.Trim()

        # 앞쪽 \ 또는 / 제거
        $script:SubPath = $script:SubPath -replace '^[\\/]+', ''

        # 뒤쪽 \ 또는 / 제거
        $script:SubPath = $script:SubPath -replace '[\\/]+$', ''

        if (-not [string]::IsNullOrWhiteSpace($script:SubPath)) {
            break
        }

        Write-Host "경로를 입력해주세요." -ForegroundColor Red
    }


    # 설정 저장
    $config = @{
        Drive   = $script:Drive
        SubPath = $script:SubPath
    }

    # ★ 수정된 부분
    $config | Export-Clixml -Path $configPath

    Write-Host ""
    Write-Host "설정이 저장되었습니다." -ForegroundColor Green
    Write-Host "저장 경로: $configPath" -ForegroundColor DarkGray

    Start-Sleep -Seconds 1
}


# ------------------------------------------------------------
# 4. 저장된 설정 불러오기
# ------------------------------------------------------------
if (Test-Path -LiteralPath $configPath) {

    try {

        $config = Import-Clixml -Path $configPath

        $script:Drive   = $config.Drive
        $script:SubPath = $config.SubPath

        # 설정값이 비어있는 경우 다시 설정
        if (
            [string]::IsNullOrWhiteSpace($script:Drive) -or
            [string]::IsNullOrWhiteSpace($script:SubPath)
        ) {
            Set-SDPath
        }

    }
    catch {

        Write-Host "저장된 설정 파일을 읽을 수 없습니다." -ForegroundColor Yellow
        Write-Host "경로를 다시 설정합니다." -ForegroundColor Yellow

        Set-SDPath
    }

}
else {

    Set-SDPath
}


# ------------------------------------------------------------
# 5. 예 / 아니오 확인 함수
# ------------------------------------------------------------
function Prompt-Confirm {

    while ($true) {

        Write-Host ""
        Write-Host "경고: 선택한 경로의 하위 폴더 및 이미지 등이 삭제됩니다." -ForegroundColor Yellow
        Write-Host "이 작업은 취소할 수 없습니다." -ForegroundColor Yellow

        $ans = Read-Host "계속하시겠습니까? (예/아니오/yes/no/y/n)"

        $ans = $ans.Trim()


        # ★ 수정된 부분
        if ($ans -match '^(예|yes|y)$') {

            return $true

        }
        elseif ($ans -match '^(아니오|no|n)$') {

            return $false

        }
        else {

            Write-Host ""
            Write-Host "잘못된 입력입니다." -ForegroundColor Red
            Write-Host "예 / 아니오 / yes / no / y / n 중 하나를 입력해주세요." -ForegroundColor Red
        }
    }
}


# ------------------------------------------------------------
# 6. 삭제 처리 함수
# ------------------------------------------------------------
function Run-Cleanup {

    param (
        [Parameter(Mandatory = $true)]
        [array]$Targets
    )


    # 기본 Output 경로
    $basePath = "$($script:Drive):\$($script:SubPath)\output"


    Write-Host ""
    Write-Host "=========================================" -ForegroundColor DarkGray
    Write-Host "삭제 대상 확인" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor DarkGray

    foreach ($target in $Targets) {

        # ★ 수정된 Join-Path
        $targetPath = Join-Path -Path $basePath -ChildPath $target

        Write-Host " - $targetPath"
    }

    Write-Host "=========================================" -ForegroundColor DarkGray


    $confirm = Prompt-Confirm


    if (-not $confirm) {

        Write-Host ""
        Write-Host "작업이 취소되었습니다. 메인 메뉴로 돌아갑니다." -ForegroundColor Yellow

        Start-Sleep -Seconds 2

        return
    }


    Write-Host ""
    Write-Host "[삭제 프로세스 진행 중...]" -ForegroundColor Cyan
    Write-Host ""


    foreach ($target in $Targets) {

        # ★ 수정된 Join-Path
        $targetPath = Join-Path -Path $basePath -ChildPath $target


        if (Test-Path -LiteralPath $targetPath) {

            Write-Host "정리 중: $targetPath" -ForegroundColor White

            try {

                # ------------------------------------------------
                # 대상 폴더 자체는 유지하고
                # 내부의 모든 파일/폴더만 삭제
                # ------------------------------------------------
                Get-ChildItem `
                    -LiteralPath $targetPath `
                    -Force `
                    -ErrorAction Stop |
                Remove-Item `
                    -Force `
                    -Recurse `
                    -ErrorAction Stop


                Write-Host " -> 삭제 완료" -ForegroundColor Green
                Write-Host ""
            }
            catch {

                Write-Host " -> 삭제 중 오류가 발생했습니다." -ForegroundColor Red
                Write-Host " -> $($_.Exception.Message)" -ForegroundColor Red
                Write-Host ""
            }

        }
        else {

            Write-Host "경로를 찾을 수 없음 (건너뜀):" -ForegroundColor DarkGray
            Write-Host " -> $targetPath" -ForegroundColor DarkGray
            Write-Host ""
        }
    }


    Write-Host "=========================================" -ForegroundColor DarkGray
    Write-Host "작업이 완료되었습니다." -ForegroundColor Green
    Write-Host "스크립트가 5초 후 자동 종료됩니다..." -ForegroundColor Yellow
    Write-Host "=========================================" -ForegroundColor DarkGray

    Start-Sleep -Seconds 5

    exit
}


# ------------------------------------------------------------
# 7. 메인 메뉴
# ------------------------------------------------------------
while ($true) {

    Clear-Host

    $currentOutputPath = "$($script:Drive):\$($script:SubPath)\output"


    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host " SD 출력 폴더(Output) 정리 스크립트" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan

    Write-Host ""
    Write-Host "현재 타겟 경로:"
    Write-Host "$currentOutputPath" -ForegroundColor Green

    Write-Host ""
    Write-Host "========================================="

    Write-Host "정리 대상을 선택하세요:"
    Write-Host ""

    Write-Host "1. img2img 폴더 하위 항목 정리"
    Write-Host "   - img2img-grids"
    Write-Host "   - img2img-images"

    Write-Host ""

    Write-Host "2. txt2img 폴더 하위 항목 정리"
    Write-Host "   - txt2img-grids"
    Write-Host "   - txt2img-images"

    Write-Host ""

    Write-Host "3. extras-img 폴더 하위 항목 정리"
    Write-Host "   - extras-images"

    Write-Host ""
    Write-Host "C. SD 경로 변경"
    Write-Host "E. 스크립트 종료"

    Write-Host ""
    Write-Host "========================================="


    $choice = Read-Host "메뉴 입력"


    switch ($choice.Trim()) {

        '1' {

            Run-Cleanup -Targets @(
                'img2img-grids'
                'img2img-images'
            )
        }


        '2' {

            Run-Cleanup -Targets @(
                'txt2img-grids'
                'txt2img-images'
            )
        }


        '3' {

            Run-Cleanup -Targets @(
                'extras-images'
            )
        }


        { $_ -match '^[cC]$' } {

            Set-SDPath
        }


        { $_ -match '^[eE]$' } {

            Write-Host ""
            Write-Host "스크립트를 종료합니다." -ForegroundColor Yellow

            Start-Sleep -Seconds 1

            exit
        }


        default {

            Write-Host ""
            Write-Host "잘못된 선택입니다. 다시 선택해주세요." -ForegroundColor Red

            Start-Sleep -Seconds 1
        }
    }
}
