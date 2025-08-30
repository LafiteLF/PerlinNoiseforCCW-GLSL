#version 300 es
#ifdef GL_ES
precision mediump float; // 设置浮点类型的默认精度
#endif
// *** 警告：不要更改上面的代码 *** //
// 关于在 Gandi IDE 中使用着色器的更多信息，请访问：https://getgandi.com/cn/blog/glsl-in-gandi-ide

// *** 配置 *** //
// 下面的行设置了 'time' 变量的步进值，默认为 1。
// 在通常以 60 fps 运行的浏览器中，每帧会将 'time' 递增 'step'（即 time += step）。

// *** 默认变量 *** //
uniform bool byp; // 绕过标志，用于启用或禁用着色器效果
uniform float aime; // 自定义时间变量
in vec2 vUv; // 传递给片段着色器的纹理坐标
out vec4 fragColor; // 输出片段颜色

// 当定义以下行时，当前屏幕内容作为纹理传递给变量 'tDiffuse'。
// 注释掉或更改 'tDiffuse' 的名字将自动禁用此功能。
uniform sampler2D tDiffuse;
// 取消注释，可以启用计时器， 如果启动了计时器，上面设置的 step 才会生效。 此示例项目不需要使用计时器
uniform float time;

vec3  iResolution; // 分辨率变量（用于适配shadertoy风格）
float iTime; // 时间变量（用于适配shadertoy风格）

#define SINGLE_SAMPLE 1 // 定义单采样模式

float minh = 0.0, maxh = 6.0; // 地形高度范围
vec3 nn = vec3(0); // 法线存储变量

// 哈希函数：生成伪随机数
float hash(float n)
{
    return fract(sin(n) * 43758.5453);
}

// 3D噪声函数：基于整数坐标生成随机值
float noise(vec3 p)
{
    return hash(p.x + p.y*57.0 + p.z*117.0);
}

// 值噪声函数：在3D空间中进行三线性插值
float valnoise(vec3 p)
{
    vec3 c = floor(p); // 整数部分
    vec3 f = smoothstep(0., 1., fract(p)); // 小数部分，使用平滑插值
    return mix(
        mix (mix(noise(c + vec3(0, 0, 0)), noise(c + vec3(1, 0, 0)), f.x),
             mix(noise(c + vec3(0, 1, 0)), noise(c + vec3(1, 1, 0)), f.x), f.y),
        mix (mix(noise(c + vec3(0, 0, 1)), noise(c + vec3(1, 0, 1)), f.x),
             mix(noise(c + vec3(0, 1, 1)), noise(c + vec3(1, 1, 1)), f.x), f.y),
        f.z);
}

// 分形布朗运动：叠加多个频率的噪声
float fbm(vec3 p)
{
    float f = 0.;
    for(int i = 0; i < 5; ++i)
        f += (valnoise(p * exp2(float(i))) - .5) / exp2(float(i));
    return f;
}

// 高度函数：根据地面的x,z坐标计算高度
float height(vec2 p)
{
    // 使用fbm生成基础高度，并进行非线性变换
    float h = mix(minh, maxh * 1.3, pow(clamp(.2 + .8 * fbm(vec3(p / 6., 0.)), 0., 1.), 1.3));
    h += valnoise(vec3(p, .3)); // 添加细节噪声
    return h;
}

// 光线追踪函数：从原点o沿方向r进行追踪，返回交点位置
vec3 tr2(vec3 o,vec3 r)
{
    // 如果起点在最大高度以上，先调整到最大高度处
    if(o.y > maxh)
        o += r * (maxh - o.y) / r.y;
    
    vec2 oc = vec2(floor(o.x), floor(o.z)), c; // 当前网格单元坐标
    vec2 dn = normalize(vec2(-1, 1)); // 对角线方向
    vec3 ta, tb, tc; // 三角形三个顶点

    // 初始化三角形顶点
    ta = vec3(oc.x, height(oc + vec2(0, 0)), oc.y);
    tc = vec3(oc.x + 1., height(oc + vec2(1, 1)), oc.y + 1.);
    
    // 根据位置选择对角线分割方式
    if(fract(o.z) < fract(o.x))
        tb = vec3(oc.x + 1., height(oc + vec2(1, 0)), oc.y + 0.);
    else
        tb = vec3(oc.x, height(oc + vec2(0, 1)), oc.y + 1.);

    float t0 = 1e-4, t1; // 光线参数，t0起始，t1结束

    // 计算光线斜率
    vec2 dd = vec2(1) / r.xz;
    float dnt = 1.0 / dot(r.xz, dn);
    
    float s = max(sign(dnt), 0.);
    c = ((oc + max(sign(r.xz), 0.)) - o.xz) * dd;

    vec3 rs = sign(r); // 光线方向符号

    // 主光线追踪循环
    for(int i = 0; i < 450; ++i)
    {  
        t1 = min(c.x, c.y); // 找到最近的轴对齐平面交点

        // 测试光线与对角线平面的交点
        float dt = dot(oc - o.xz, dn) * dnt;
        if(dt > t0 && dt < t1)
            t1 = dt;
 
#if !SINGLE_SAMPLE
        // 多采样模式：为所有三个顶点采样高度
        vec2 of = (dot(o.xz + r.xz * (t0 + t1) * .5 - oc, dn) > 0.) ? vec2(0, 1) : vec2(1, 0);
        tb = vec3(oc.x + of.x, height(oc + of), oc.y + of.y);
        ta = vec3(oc.x, height(oc + vec2(0, 0)), oc.y);
        tc = vec3(oc.x + 1., height(oc + vec2(1, 1)), oc.y + 1.);
#endif        

        // 测试光线与三角形平面的交点
        vec3 hn = cross(ta - tb, tc - tb); // 计算法线
        float hh = dot(ta - o, hn) / dot(r, hn); // 计算交点参数

        if(hh > t0 && hh < t1)
        {
            // 找到与三角形的交点
            nn = hn; // 存储法线
            return o + r * hh; // 返回交点位置
        }

#if SINGLE_SAMPLE
        vec2 offset;
        
        // 获取"轴选择器"，对于近(相交)轴为1.0，远轴为0.0
        vec2 ss = step(c, c.yx);

        // 获取下一个顶点高度的坐标偏移
        if(dt >= t0 && dt < c.x && dt < c.y)
        {
            offset = vec2(1. - s, s);
        }
        else
        {
            offset = dot(r.xz, ss) > 0. ? vec2(2, 1) : vec2(-1, 0);

            if(c.y < c.x)
                offset = offset.yx;
        }

        // 获取下一个顶点
        vec3 tnew = vec3(oc + offset, height(oc + offset)).xzy;

        // 更新三角形顶点
        if(dt >= t0 && dt < c.x && dt < c.y)
        {
            tb = tnew;
        }
        else
        {
            // 根据光线轴向符号交换顶点顺序
            if(dot(r.xz, ss) > 0.)
            {
                ta = tb;
                tb = tc;
                tc = tnew;
            }
            else
            {
                tc = tb;
                tb = ta;
                ta = tnew;
            }

            // 沿网格步进到下一个单元
            oc.xy += rs.xz * ss;
            c.xy += dd.xy * rs.xz * ss;
        }
#else
        // 多采样模式的处理
        vec2 ss = step(c, c.yx);
        
        if(dt < t0 || dt >= c.x || dt >= c.y)
        {
            // 沿网格步进到下一个单元
            oc.xy += rs.xz * ss;
            c.xy += dd.xy * rs.xz * ss;
        }
        
#endif
        t0 = t1; // 更新起始参数

        // 测试光线是否离开了上部Y边界
        if(((maxh - o.y) / r.y < t0 && r.y > 0.) || t0 > 200.)
            return vec3(10000); // 返回远点表示无交点

    }
    return vec3(10000); // 超过迭代次数，返回远点
}

// 光线方向函数：根据屏幕UV坐标计算光线方向
vec3 rfunc(vec2 uv)
{
    vec3 r = normalize(vec3(uv.xy, -1.3));
    float ang = .7; // 旋转角度
    r.yz *= mat2(cos(ang), sin(ang), -sin(ang), cos(ang)); // 应用旋转矩阵
    return r;
}

// 棋盘格函数：生成棋盘格图案
float chequer(vec2 p)
{
    return step(0.5, fract(p.x + step(0.5, fract(p.y)) * 0.5));
}

// 主图像函数：Shadertoy风格的主函数
void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    vec2 uv = fragCoord / iResolution.xy; // 标准化坐标
    
    vec2 t = uv * 2. - 1. + 1e-3; // 转换为[-1,1]范围
    t.x *= iResolution.x / iResolution.y; // 保持宽高比

    // 设置主光线：原点随时间移动
    vec3 o = vec3(1.4, 9.5, -iTime), r = rfunc(t);

    // 追踪主光线
    vec3 rp = tr2(o, r);

    // 表面法线
    vec3 n = normalize(nn);
    if(n.y < 0.)
        n =- n; // 确保法线朝上

    // 棋盘格图案
    vec3 col = vec3(mix(.8, 1., chequer(rp.xz / 2.)));

    // 根据位置调整颜色
    if(fract(rp.z) < fract(rp.x))
		col *= .7;
    
    // 光照方向
    vec3 ld = normalize(vec3(1.5, 1, -2));

    // 方向性阴影（通过光线追踪实现）
    vec3 rp2 = tr2(rp + n*1e-4 + ld * 1e-4, ld);
    if(distance(rp, rp2) < 1000.)
        col *= .4 * vec3(.65, .65, 1); // 应用阴影

    // 基础着色
    col *= mix(vec3(1, .8, .5) / 2., vec3(.3, 1, .3) / 4., 1. - clamp(rp.y / 2., 0., 1.));
    col = mix(col, vec3(1) * .7, pow(clamp((rp.y - 2.5) / 2., 0., 1.), 2.)); // 高度相关颜色

    // 方向光衰减
    col *= pow(.5 + .5 * dot(n, ld), 1.);
    
    // 雾效：根据距离混合颜色
    col = mix(vec3(.65, .65, 1), col, exp2(-distance(rp, o) / 1024.));

    // 钳制并伽马校正
    fragColor.rgb = pow(clamp(col * 2., 0., 1.), vec3(1. / 2.2));
}

// 主函数：GLSL ES入口点
void main() {
    if (!byp) {
        // 如果不绕过，执行自定义着色器效果
        iResolution = vec3(640.0f, 360.0f, 0.0f); // 设置分辨率
        iTime = aime / 10.0f; // 设置时间

        // 调用主图像函数
        mainImage(fragColor, vUv * vec2(640.0f, 360.0f));
    } else {
        // 如果启用了绕过，使用原始纹理颜色
        fragColor = texture(tDiffuse, vUv);
    }
}