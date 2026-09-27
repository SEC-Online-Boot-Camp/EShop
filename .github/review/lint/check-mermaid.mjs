// Markdown 内の ```mermaid ブロックを抜き出し、mermaid のパーサで構文を検証する。
//
// 使い方: node .github/review/lint/check-mermaid.mjs <file.md> [...]
// 構文エラーがあれば GitHub Actions の注釈（::error file=...,line=...::）を出し、終了コード 1 で終える。
//
// 描画（mmdc + ヘッドレス Chromium）はせず、構文の解析（mermaid.parse）だけを行う。
// mermaid は DOM を前提にしているため、jsdom で最小限の window / document を用意する。
import { readFileSync } from 'node:fs'
import { JSDOM } from 'jsdom'

const dom = new JSDOM('<!doctype html><html><body></body></html>')
globalThis.window = dom.window
globalThis.document = dom.window.document

const { default: mermaid } = await import('mermaid')
mermaid.initialize({ startOnLoad: false })

// ```mermaid 〜 ``` を、開始行（フェンスの行、1 始まり）付きで返す
function extractBlocks(text) {
  const blocks = []
  let current = null
  text.split(/\r?\n/).forEach((line, i) => {
    if (current === null) {
      if (/^```mermaid[ \t]*$/.test(line)) current = { start: i + 1, lines: [] }
    } else if (/^```[ \t]*$/.test(line)) {
      blocks.push(current)
      current = null
    } else {
      current.lines.push(line)
    }
  })
  return blocks
}

let failed = 0
let checked = 0
for (const file of process.argv.slice(2)) {
  for (const block of extractBlocks(readFileSync(file, 'utf8'))) {
    checked++
    try {
      await mermaid.parse(block.lines.join('\n'))
    } catch (err) {
      failed++
      const message = String(err?.message ?? err)
      // "Parse error on line N:" の N はブロック内の行番号。ファイルの行番号に直す
      const m = message.match(/on line (\d+)/)
      const line = m ? block.start + Number(m[1]) : block.start
      const oneLine = message.replace(/\s+/g, ' ').trim()
      console.log(`::error file=${file},line=${line}::Mermaid の構文エラー: ${oneLine}`)
    }
  }
}

console.log(`Mermaid: ${checked} ブロックを検査し、${failed} 件の構文エラー`)
process.exit(failed > 0 ? 1 : 0)
