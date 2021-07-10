<?php
declare(strict_types=1);

namespace dev\example\service\tasks\word;

use dev\winterframework\dtce\task\worker\AbstractTaskWorker;
use dev\winterframework\dtce\task\worker\output\NumericOutput;
use dev\winterframework\dtce\task\worker\TaskOutput;

class WordCounter extends AbstractTaskWorker {

    public function work(mixed $input): TaskOutput {
        if (!is_scalar($input)) {
            return new NumericOutput(0);
        }

        $input = '' . $input;

        return new NumericOutput(str_word_count($input));
    }

}