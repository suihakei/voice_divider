import os
import wav
import strutils
import strformat
import locks
import wNim/[wApp, wFrame, wPanel, wStaticText, wTextCtrl, wButton, wFileDialog, wDirDialog, wMessageDialog, wCheckBox]


##
## バージョン
##
const BUILD_VERSION = "0.30"


##
## 定数
##
const STATUS_DEFAULT_MESSAGE = "やってることがここに表示されます"


##
## 前方宣言
##
proc divideWav(data: tuple[targetWavFilePath: string, outputDirPath: string, threshold: float, silenceTimeToCut: float, trimSlienceTime: float]) {.thread.}


##
## グローバル変数
##
var thread: Thread[tuple[targetWavFilePath: string, outputDirPath: string, threshold: float, silenceTimeToCut: float, trimSlienceTime: float]]


# GUI設定
let app = App()
let frame = Frame(title="Suihack Voice Divider ver. " & BUILD_VERSION)
frame.dpiAutoScale:
    frame.minSize = (650, 350)
    frame.maxSize = (650, 350)
    frame.disableMaximizeButton()
let panel = Panel(frame)


# GUI Elements
let labelCutTargetFile = StaticText(panel, label="カット対象WAVファイル", pos=(10, 5), size=(150, 21))
let textCutTargetFile = TextCtrl(panel, pos=(10, 25), size=(550, 19), style=wBorderSimple)
let buttonTargetFileSelect = Button(panel, pos=(570, 5), size=(50, 40), label="選択")

let labelChannelNum = StaticText(panel, label="チャンネル数", pos=(10, 55), size=(80, 21))
let textChannelNum = TextCtrl(panel, pos=(85, 53), size=(30, 19), style=wBorderSimple or wTeReadOnly)
let labelsamplingFrequency = StaticText(panel, label="サンプリング周波数", pos=(130, 55), size=(100, 21))
let textsamplingFrequency = TextCtrl(panel, pos=(230, 53), size=(80, 19), style=wBorderSimple or wTeReadOnly)
let labelquantizationBits = StaticText(panel, label="量子化ビット数", pos=(350, 55), size=(80, 21))
let textquantizationBits = TextCtrl(panel, pos=(435, 53), size=(30, 19), style=wBorderSimple or wTeReadOnly)

let labelThresholdVolume = StaticText(panel, label="無音判別しきい値", pos=(10, 100), size=(100, 21))
let textThresholdVolume = TextCtrl(panel, pos=(110, 100), size=(80, 19), style=wBorderSimple)

let labelSilenceTimeToCut = StaticText(panel, label="カットポジション判別秒数", pos=(10, 125), size=(130, 21))
let textSilenceTimeToCut = TextCtrl(panel, pos=(145, 125), size=(80, 19), style=wBorderSimple)

let checkBoxTrimSilence = CheckBox(panel, label="前後の無音のカット", pos=(10, 145))
let labelTrimSilence = StaticText(panel, label="前後の無音を残す秒数", pos=(145, 150), size=(130, 21))
let textTrimSilence = TextCtrl(panel, pos=(280, 148), size=(80, 19), style=wBorderSimple)

let labelOutputFolder = StaticText(panel, label="出力先ディレクトリ", pos=(10, 180), size=(150, 21))
let textOutputFolder = TextCtrl(panel, pos=(10, 200), size=(550, 19), style=wBorderSimple)
let buttonOutputFolderSelect = Button(panel, pos=(570, 180), size=(50, 40), label="選択")

let buttonStartDivide = Button(panel, pos=(470, 240), size=(150, 40), label="無音でカット開始")
let textStatus = TextCtrl(panel, value=STATUS_DEFAULT_MESSAGE, pos=(10, 250), size=(450, 21), style=wAlignCentre or wTeReadOnly)


#
# デフォルト値
#
textThresholdVolume.setValue("0.05")
textSilenceTimeToCut.setValue("2")
textTrimSilence.setValue("0.5")


#
# WAVファイル選択ボタン押下時
#
buttonTargetFileSelect.wEvent_Button do (event: wEvent):
    let file = FileDialog(frame, message="WAVファイルを選択", wildcard = "*.wav").display()
    if file.len() > 0:
        if wav.isWav(file[0]) == false:
            MessageDialog(frame, "WAVファイルではないようです。\n解析に失敗しました", caption="Path").display()
            return

        textCutTargetFile.setValue(file[0])


#
# 分割ファイル出力先
#
buttonOutputFolderSelect.wEvent_Button do (event: wEvent):
    let dir = DirDialog(frame, message="出力先を選択").display()
    if dir.len() > 0:
        textOutputFolder.setValue(dir)


#
# 無音でカット開始
#
buttonStartDivide.wEvent_Button do (event: wEvent):
    let wavFile = textCutTargetFile.getValue()
    let dir = textOutputFolder.getValue()
    let threshold = parseFloat(textThresholdVolume.getValue())
    let silenceTimeToCut = parseFloat(textSilenceTimeToCut.getValue())
    let isTrimSilence = checkBoxTrimSilence.isChecked()
    var trimSlienceTime = parseFloat(textTrimSilence.getValue())

    if wavFile == "":
        MessageDialog(frame, "WAVファイルが指定されていません").display()
        return

    if dir == "":
        MessageDialog(frame, "出力先フォルダが指定されていません").display()
        return

    if wav.isWav(wavFile) == false:
        MessageDialog(frame, "WAVファイルではないようです。\n解析に失敗しました").display()
        return

    if threshold < 0 or 1 < threshold:
        MessageDialog(frame, "しきい値は0～1の間で指定してください").display()
        return

    if silenceTimeToCut <= 0:
        MessageDialog(frame, "カットポジション判別秒数は0.1以上で指定してください").display()
        return

    if isTrimSilence == false:
        trimSlienceTime = 0.0

    if isTrimSilence == true and trimSlienceTime < 0:
        MessageDialog(frame, "前後の無音のカット秒数は0以上で指定してください").display()
        return

    createThread(thread, divideWav, (wavFile, dir, threshold, silenceTimeToCut, trimSlienceTime))


frame.center()
frame.show()
app.mainLoop()


proc divideWav(data: tuple[targetWavFilePath: string, outputDirPath: string, threshold: float, silenceTimeToCut: float, trimSlienceTime: float]) {.thread.} =
    {.gcsafe.}:
        textStatus.setValue("WAVファイルの分割中...")

        let wave = wav.readWave(data.targetWavFilePath)
        let slicedWaves = wav.divideBySilence(wave, data.threshold, data.silenceTimeToCut)

        # WAV情報を表示
        textChannelNum.setValue($wave.getChannel())
        textsamplingFrequency.setValue($wave.getSamplingFrequency())
        textquantizationBits.setValue($wave.getQuantizationBits())

        var outputCnt = 1
        let allFileNum = slicedWaves.len()
        for sw in slicedWaves:
            textStatus.setValue($outputCnt & "/" & $allFileNum & "個のファイルを書き出し中")

            var slicedWave = sw

            # すべて無音なら書き出さない
            if slicedWave.isAllSilence(data.threshold) == true:
                continue

            # 前後の無音をカット
            if data.trimSlienceTime > 0:
                slicedWave = wav.trimSilence(slicedWave, data.threshold, data.silenceTimeToCut, data.trimSlienceTime)

            # 書き出し
            wav.writeWave(data.outputDirPath / $outputCnt & ".wav", slicedWave)

            outputCnt += 1
        
        textStatus.setValue(STATUS_DEFAULT_MESSAGE)