---
layout: post
title: mybatis-generator使用
---



# {{page.title}}

------

## 一、mybatis-generator简介

mybatis-generator可以帮助我们根据数据源表结构，快速生成访问数据库的代码。常用的有3种方式使用它：
(1)  命令行的格式。```    java -jar mybatis-generator-core-x.x.x.jar -configfile generatorConfig.xml -overwrite ```

(2) maven插件的方式。
(3) java代码的方式。
使用maven插件是最为简便和常用的方式。下面详细介绍下maven插件方式使用的过程。
## 二、快速搭建mybatis-generator框架
搭建mybatis-generator使用环境，可以大概分为3步骤。
1. 初始化环境：包括项目依赖，引入maven插件，配置插件。
2. 配置generatorConfig.xml文件。
3. 生成的代码并打包发布。

### 初始化环境
(1) 新增mybatis、mybatis-generator依赖
```
        <dependency>
            <groupId>org.mybatis</groupId>
            <artifactId>mybatis</artifactId>
            <version>3.4.6</version>
        </dependency>
        <dependency>
            <groupId>org.mybatis.generator</groupId>
            <artifactId>mybatis-generator-core</artifactId>
            <version>1.3.7</version>
        </dependency>
```
(2)

## 三、使用注意事项


