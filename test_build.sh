#!/bin/bash

# 快速构建测试脚本
echo "🔧 开始检查项目文件..."

cd "/Users/jaredlee/Documents/Work/tianji/TianjiApp"

echo "📁 检查Swift文件..."
find . -name "*.swift" | while read file; do
    echo "检查: $file"
    # 检查基本语法错误
    if ! grep -q "import" "$file"; then
        echo "⚠️  警告: $file 可能缺少导入语句"
    fi
done

echo "📊 检查项目结构..."
if [ ! -f "TianjiApp.xcodeproj/project.pbxproj" ]; then
    echo "❌ 错误: 找不到项目文件"
    exit 1
fi

echo "✅ 基本检查完成"
echo "💡 提示: 在Xcode中打开项目以获取完整的编译错误信息"