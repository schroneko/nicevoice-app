#!/usr/bin/env node

import { writeFileSync, mkdirSync, existsSync, readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const outputDir = resolve(__dirname, '../benchmark-audio');

const devVarsPath = resolve(__dirname, '../.dev.vars');
if (existsSync(devVarsPath)) {
  const content = readFileSync(devVarsPath, 'utf-8');
  for (const line of content.split('\n')) {
    const match = line.match(/^(\w+)=(.*)$/);
    if (match) {
      process.env[match[1]] = match[2];
    }
  }
}

const testCases = [
  { id: 'basic_greeting', text: 'こんにちは' },
  { id: 'polite_request', text: 'お願いいたします' },
  { id: 'question', text: '徹底的に調べてもらってもいいですか' },
  { id: 'repeated_polite', text: 'お願いいたします。お願いいたします。お願いいたします。' },
  { id: 'filler_words', text: 'えーっと、あのー、それからですね' },
  { id: 'technical', text: 'クロードコードを使って開発しています' },
  { id: 'long_sentence', text: '本日はお忙しい中ご参加いただきまして誠にありがとうございます' },
  { id: 'numbers', text: '2024年12月28日の会議です' },
  { id: 'mixed', text: 'Swiftでアプリを作成してGitHubにプッシュしました' },
  { id: 'pause_mid', text: 'これは、とても重要な、お知らせです' },
];

function getApiKey() {
  if (process.env.OPENAI_API_KEY) {
    return process.env.OPENAI_API_KEY;
  }
  try {
    return execSync('op item get "OPENAI_API_KEY" --fields credential --reveal', {
      encoding: 'utf-8',
    }).trim();
  } catch {
    throw new Error('OPENAI_API_KEY が見つかりません。環境変数か 1Password を設定してください。');
  }
}

const apiKey = getApiKey();

async function generateAudio(testCase) {

  const response = await fetch('https://api.openai.com/v1/audio/speech', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'gpt-4o-mini-tts',
      input: testCase.text,
      voice: 'nova',
      response_format: 'wav',
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`TTS API error: ${response.status} - ${error}`);
  }

  const audioBuffer = await response.arrayBuffer();
  const outputPath = resolve(outputDir, `${testCase.id}.wav`);
  writeFileSync(outputPath, Buffer.from(audioBuffer));

  return `benchmark-audio/${testCase.id}.wav`;
}

async function main() {
  console.log('🎵 OpenAI TTS でテスト音声を生成\n');

  if (!existsSync(outputDir)) {
    mkdirSync(outputDir, { recursive: true });
  }

  const manifest = [];

  for (const testCase of testCases) {
    process.stdout.write(`  ${testCase.id.padEnd(20)}`);
    try {
      const path = await generateAudio(testCase);
      console.log('✅');
      manifest.push({
        id: testCase.id,
        text: testCase.text,
        audioPath: path,
      });
    } catch (error) {
      console.log(`❌ ${error.message}`);
    }
  }

  const manifestPath = resolve(outputDir, 'manifest.json');
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));

  console.log(`\n✅ 完了: ${manifest.length}/${testCases.length} ファイル生成`);
  console.log(`📁 出力先: ${outputDir}`);
}

main().catch(console.error);
