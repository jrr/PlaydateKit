import PlaydateKit

// MARK: - GameConstants

enum GameConstants {
    static let initialBallDirection = degreesToRadians(-30)
    static let initialBallSpeed = sqrtf(4 * 4 + 5 * 5)

    static let cpuPaddleSpeed: Float = 3.5

    /// When using the d-pad, the player's paddle moves this fast
    static let playerPaddleSpeed: Float = 4.5

    /// When predicting the path of the ball, the CPU adds a random error within the range of `[-n, n]`.
    static let cpuAngleError = degreesToRadians(6)
}

// MARK: - Game

final class Game: PlaydateGame {
    // MARK: Lifecycle

    init() {
        [
            playerPaddle, computerPaddle,
            ball,
            topWall, bottomWall, leftWall, rightWall
        ].forEach { $0.addToDisplayList() }

        playerPaddle.position = Point(x: 10, y: (Float(Display.height) / 2) - (playerPaddle.bounds.height / 2))
        computerPaddle.position = Point(
            x: Float(Display.width - 10) - computerPaddle.bounds.width,
            y: Float(Display.height / 2) - (computerPaddle.bounds.height / 2)
        )
        ball.position = Point(x: Display.width / 2, y: 10)
    }

    // MARK: Internal

    enum State {
        case playing
        case gameOver
    }

    var state: State = .playing
    var score: (player: Int, computer: Int) = (0, 0)
    let winningScore = 11
    let playerPaddle = PlayerPaddle()
    let computerPaddle = ComputerPaddle()
    let ball = Ball()

    let topWall = Wall(bounds: Rect(x: 0, y: -1, width: Display.width, height: 1))
    let bottomWall = Wall(bounds: Rect(x: 0, y: Display.height, width: Display.width, height: 1))
    let leftWall = Wall(bounds: Rect(x: -1, y: 0, width: 1, height: Display.height))
    let rightWall = Wall(bounds: Rect(x: Display.width, y: 0, width: 1, height: Display.height))

    var hasWinner: Bool { score.player >= winningScore || score.computer >= winningScore }

    func update() -> Bool {
        switch state {
        case .playing:
            Sprite.updateAndDrawDisplayListSprites()
        case .gameOver:
            if System.buttonState.current.contains(.a) {
                score = (0, 0)
                state = .playing
            }

            // TODO: - Center properly
            Graphics.drawText(
                "Game Over",
                at: Point(x: (Display.width / 2) - 40, y: (Display.height / 2) - 20)
            )
            Graphics.drawText(
                "Press Ⓐ to play again",
                at: Point(x: (Display.width / 2) - 80, y: Display.height / 2)
            )
        }

        Graphics.drawText("\(score.player)", at: Point(x: (Display.width / 2) - 80, y: 10))
        Graphics.drawText("\(score.computer)", at: Point(x: (Display.width / 2) + 80, y: 10))
        Graphics.drawLine(
            Line(
                start: Point(x: Display.width / 2, y: 0),
                end: Point(x: Display.width / 2, y: Display.height)
            ),
            lineWidth: 1,
            color: .pattern((0x0, 0x0, 0xFF, 0xFF, 0x0, 0x0, 0xFF, 0xFF))
        )

        return true
    }
}

// MARK: - Wall

class Wall: Sprite.Sprite {
    init(bounds: Rect) {
        super.init()
        self.bounds = bounds
        collideRect = Rect(origin: .zero, width: bounds.width, height: bounds.height)
    }
}

// MARK: - Ball

typealias Vector = Point

func vectorToRadians(_ vector: Vector) -> Float {
    atan2f(vector.y, vector.x)
}

func radiansToUnitVector(_ radians: Float) -> Vector {
    Vector(x: cosf(radians), y: sinf(radians))
}

func degreesToRadians(_ degrees: Float) -> Float {
    degrees * Float.pi / 180.0
}

func radiansToDegrees(_ radians: Float) -> Float {
    radians * 180.0 / Float.pi
}

// MARK: - Ball

class Ball: Sprite.Sprite {
    // MARK: Lifecycle

    override init() {
        super.init()
        bounds = .init(x: 0, y: 0, width: 8, height: 8)
        collideRect = bounds
        velocity = radiansToUnitVector(GameConstants.initialBallDirection) * GameConstants.initialBallSpeed
    }

    // MARK: Internal

    var velocity = Vector(x: 0, y: 0)
    var bounceCount = 0

    static func computeNewVelocity(collisionPoint: Float, speed: Float, direction: Bool) -> Vector {
        // Maximum and minimum angle from vertical
        let minReturnAngle = degreesToRadians(20)
        let returnAngleRange = Float.pi - 2 * minReturnAngle
        let selectedReturnBearing = Float.pi / 2 - minReturnAngle - collisionPoint * returnAngleRange

        let unitVector = radiansToUnitVector(selectedReturnBearing)

        let flip: Float = direction ? -1 : 1

        return Vector(x: speed * unitVector.x * flip, y: speed * unitVector.y)
    }

    func reset() {
        position = Point(x: Display.width / 2, y: 10)
        velocity.x *= Bool.random() ? 1 : -1
        velocity.y = abs(velocity.y)
        bounceCount = 0
    }

    func speed() -> Float {
        sqrtf(velocity.x * velocity.x + velocity.y * velocity.y)
    }

    override func update() {
        let collisionInfo = moveWithCollisions(
            goal: position + velocity
        )
        for collision in collisionInfo.collisions {
            if collision.other == game.leftWall {
                game.score.computer += 1
                game.ball.reset()
                if game.hasWinner { game.state = .gameOver }
            } else if collision.other == game.rightWall {
                game.score.player += 1
                game.ball.reset()
                if game.hasWinner { game.state = .gameOver }
            } else {
                synth.playNote(frequency: 220.0, volume: 0.7, length: 0.1)
                if collision.normal.x != 0 {
                    let distance = collision.otherRect.center.y - collision.spriteRect.center.y
                    let positionWithinPaddle = ((distance + collision.spriteRect.height / 2 + collision.otherRect.height / 2) / (collision.spriteRect.height + collision.otherRect.height))
                    velocity = Ball.computeNewVelocity(collisionPoint: positionWithinPaddle, speed: speed(), direction: velocity.x > 0)
                }
                if collision.normal.y != 0 {
                    velocity.y *= -1
                }
                bounceCount += 1
            }
        }
    }

    /// Setting to `.slide` prevents the ball from getting stuck between the paddle and top/bottom.
    override func collisionResponse(other _: Sprite.Sprite) -> Sprite.CollisionResponseType {
        .slide
    }

    override func draw(bounds: Rect, drawRect _: Rect) {
        Graphics.fillEllipse(in: bounds)
    }

    func interceptX(x: Int, angleError: Float) -> Int {
        let deltaX = abs(Float(x) - position.x)

        let bearing = vectorToRadians(velocity) + angleError

        let slope = radiansToUnitVector(bearing)

        let timeToIntercept = deltaX / slope.x

        let yAxisIntercept = Int(position.y + slope.y * timeToIntercept)

        return clampToRange(n: yAxisIntercept, range: (0, Display.height))
    }

    // MARK: Private

    private let synth: Sound.Synth = {
        let synth = Sound.Synth()
        synth.setWaveform(.square)
        synth.setAttackTime(0.001)
        synth.setDecayTime(0.05)
        synth.setSustainLevel(0.0)
        synth.setReleaseTime(0.05)
        return synth
    }()
}

// MARK: - ComputerPaddle

class ComputerPaddle: Paddle {
    // MARK: Public

    public var targetInterceptY: Int = 0

    // MARK: Internal

    override func update() {
        let ballGoingRight = game.ball.velocity.x > 0

        let bounceCount = game.ball.bounceCount

        if !ballGoingRight {
            // slowly return to center
            let distanceToGoal = Float(Display.height / 2) - position.y
            let movement = clampToRange(n: distanceToGoal, range: (-speed / 2, speed / 2))
            moveWithCollisions(goal: position + Vector(x: 0, y: movement))
            return
        }
        if bounceCount == 0 || bounceCount != lastBounceCount {
            lastBounceCount = bounceCount
            let randomAngleError = Float.random(in: -GameConstants.cpuAngleError...GameConstants.cpuAngleError)
//            System.log("Adding error of \(radiansToDegrees(radians: randomAngleError)) degrees")
            targetInterceptY = game.ball.interceptX(x: Int(position.x), angleError: randomAngleError)
        }

        let distanceToGoal = Float(targetInterceptY) - position.y
        let movement = clampToRange(n: distanceToGoal, range: (-speed, speed))
        moveWithCollisions(goal: position + Vector(x: 0, y: movement))
    }

    // MARK: Private

    private var lastBounceCount = -1
    private var speed = GameConstants.cpuPaddleSpeed
}

// MARK: - PlayerPaddle

class PlayerPaddle: Paddle {
    // MARK: Internal

    override func update() {
        if System.isCrankDocked {
            if System.buttonState.current.contains(.down) {
                moveWithCollisions(
                    goal: position + Vector(x: 0, y: speed)
                )
            }
            if System.buttonState.current.contains(.up) {
                moveWithCollisions(
                    goal: position - Vector(x: 0, y: speed)
                )
            }
        } else {
            // 0 at the top, 1 at the bottom
            let zeroToOne: Float = (180 - abs(System.crankAngle - 180)) / 180
            let targetY = zeroToOne * Float(Display.height)
            moveWithCollisions(goal: Point(x: position.x, y: targetY))
        }
    }

    // MARK: Private

    private var speed = GameConstants.playerPaddleSpeed
}

// MARK: - Paddle

class Paddle: Sprite.Sprite {
    // MARK: Lifecycle

    override init() {
        super.init()
        bounds = .init(x: 0, y: 0, width: 8, height: 48)
        collideRect = bounds
    }

    // MARK: Internal

    override func draw(bounds: Rect, drawRect _: Rect) {
        Graphics.fillRect(bounds)
    }
}

func clampToRange<T: Comparable>(n: T, range: (T, T)) -> T {
    let (low, high) = range
    assert(low <= high)
    let a = max(n, low)
    let b = min(a, high)
    return b
}
